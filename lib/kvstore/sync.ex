defmodule KVStore.Sync do
  @moduledoc """
  Anti-entropy synchronisation process.

  Periodically compares Merkle tree root hashes between replica nodes
  that share responsibility for the same key ranges. When roots differ,
  it drills down to find divergent keys and exchanges the corresponding
  LWW-Registers, merging them on each side.
  """
  use GenServer

  alias KVStore.{Ring, Node, MerkleTree}

  require Logger

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Triggers an immediate sync round (useful for testing)."
  @spec sync_now() :: :ok
  def sync_now do
    GenServer.call(__MODULE__, :sync_now)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    interval = Application.get_env(:kvstore, :sync_interval_ms, 5_000)
    schedule_sync(interval)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:sync, state) do
    run_sync()
    schedule_sync(state.interval)
    {:noreply, state}
  end

  @impl true
  def handle_call(:sync_now, _from, state) do
    run_sync()
    {:reply, :ok, state}
  end

  ## Internal

  defp schedule_sync(interval) do
    Process.send_after(self(), :sync, interval)
  end

  defp run_sync do
    nodes = Ring.nodes()

    # Compare all pairs of nodes. In a real system you would only
    # compare nodes that share key-range responsibility; here we
    # sync all pairs for simplicity and correctness.
    pairs = for a <- nodes, b <- nodes, a < b, do: {a, b}

    Enum.each(pairs, fn {node_a, node_b} ->
      sync_pair(node_a, node_b)
    end)
  end

  defp sync_pair(node_a, node_b) do
    try do
      root_a = Node.merkle_root(node_a)
      root_b = Node.merkle_root(node_b)

      if root_a != root_b do
        tree_a = Node.merkle_tree(node_a)
        tree_b = Node.merkle_tree(node_b)

        differing_keys = MerkleTree.diff(tree_a, tree_b)

        if differing_keys != [] do
          Logger.debug(
            "Sync: #{length(differing_keys)} keys differ between #{node_a} and #{node_b}"
          )

          data_a = Node.all_data(node_a) |> Map.new()
          data_b = Node.all_data(node_b) |> Map.new()

          # Send missing/newer entries from A to B and vice versa
          entries_for_b =
            differing_keys
            |> Enum.filter(&Map.has_key?(data_a, &1))
            |> Enum.map(&{&1, Map.get(data_a, &1)})

          entries_for_a =
            differing_keys
            |> Enum.filter(&Map.has_key?(data_b, &1))
            |> Enum.map(&{&1, Map.get(data_b, &1)})

          if entries_for_b != [], do: Node.merge_data(node_b, entries_for_b)
          if entries_for_a != [], do: Node.merge_data(node_a, entries_for_a)
        end
      end
    rescue
      e ->
        Logger.warning("Sync error between #{node_a} and #{node_b}: #{inspect(e)}")
    end
  end
end
