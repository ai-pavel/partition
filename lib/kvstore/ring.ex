defmodule KVStore.Ring do
  @moduledoc """
  Consistent hash ring with virtual nodes.

  Maps keys to a set of responsible storage nodes using SHA-256 hashing.
  Each physical node is assigned multiple virtual nodes (vnodes) spread
  around the ring to ensure even distribution of keys.

  The ring is stored as a sorted list of {hash, node_id} tuples. Key
  lookup performs a binary search to find the first vnode with a hash
  >= the key's hash (wrapping around if necessary).
  """
  use GenServer

  @type node_id :: atom()
  @type vnode :: {non_neg_integer(), node_id()}

  ## Client API

  @doc "Starts the ring process."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Adds a physical node to the ring."
  @spec add_node(node_id()) :: :ok
  def add_node(node_id) do
    GenServer.call(__MODULE__, {:add_node, node_id})
  end

  @doc "Removes a physical node from the ring."
  @spec remove_node(node_id()) :: :ok
  def remove_node(node_id) do
    GenServer.call(__MODULE__, {:remove_node, node_id})
  end

  @doc """
  Returns the ordered preference list of node IDs responsible for the
  given key. The list length equals the configured replication factor.
  """
  @spec preference_list(String.t()) :: [node_id()]
  def preference_list(key) do
    GenServer.call(__MODULE__, {:preference_list, key})
  end

  @doc "Returns all registered physical node IDs."
  @spec nodes() :: [node_id()]
  def nodes do
    GenServer.call(__MODULE__, :nodes)
  end

  @doc "Returns the full vnode ring (for debugging/testing)."
  @spec ring() :: [vnode()]
  def ring do
    GenServer.call(__MODULE__, :ring)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    vnodes = Application.get_env(:kvstore, :virtual_nodes, 128)
    {:ok, %{ring: [], physical_nodes: MapSet.new(), vnodes_per_node: vnodes}}
  end

  @impl true
  def handle_call({:add_node, node_id}, _from, state) do
    if MapSet.member?(state.physical_nodes, node_id) do
      {:reply, :ok, state}
    else
      new_vnodes = generate_vnodes(node_id, state.vnodes_per_node)
      new_ring = merge_ring(state.ring, new_vnodes)
      new_physical = MapSet.put(state.physical_nodes, node_id)
      {:reply, :ok, %{state | ring: new_ring, physical_nodes: new_physical}}
    end
  end

  def handle_call({:remove_node, node_id}, _from, state) do
    new_ring = Enum.reject(state.ring, fn {_hash, nid} -> nid == node_id end)
    new_physical = MapSet.delete(state.physical_nodes, node_id)
    {:reply, :ok, %{state | ring: new_ring, physical_nodes: new_physical}}
  end

  def handle_call({:preference_list, key}, _from, state) do
    nodes = find_nodes(key, state.ring, replication_factor())
    {:reply, nodes, state}
  end

  def handle_call(:nodes, _from, state) do
    {:reply, MapSet.to_list(state.physical_nodes), state}
  end

  def handle_call(:ring, _from, state) do
    {:reply, state.ring, state}
  end

  ## Internal Functions

  @doc false
  def hash(data) do
    :crypto.hash(:sha256, to_string(data))
    |> :binary.decode_unsigned()
  end

  defp generate_vnodes(node_id, count) do
    for i <- 0..(count - 1) do
      h = hash("#{node_id}:vnode:#{i}")
      {h, node_id}
    end
    |> Enum.sort_by(fn {h, _} -> h end)
  end

  defp merge_ring(existing, new_vnodes) do
    (existing ++ new_vnodes)
    |> Enum.sort_by(fn {h, _} -> h end)
  end

  defp find_nodes(_key, [], _n), do: []

  defp find_nodes(key, ring, n) do
    key_hash = hash(key)
    ring_size = length(ring)

    # Find the starting index: first vnode with hash >= key_hash
    start_idx =
      case Enum.find_index(ring, fn {h, _} -> h >= key_hash end) do
        nil -> 0
        idx -> idx
      end

    # Walk the ring collecting distinct physical nodes
    collect_distinct_nodes(ring, start_idx, ring_size, n, [], 0)
  end

  defp collect_distinct_nodes(_ring, _idx, _size, n, acc, _steps) when length(acc) >= n do
    Enum.reverse(acc) |> Enum.take(n)
  end

  defp collect_distinct_nodes(_ring, _idx, size, _n, acc, steps) when steps >= size do
    Enum.reverse(acc)
  end

  defp collect_distinct_nodes(ring, idx, size, n, acc, steps) do
    {_h, node_id} = Enum.at(ring, rem(idx, size))

    new_acc =
      if node_id in acc do
        acc
      else
        [node_id | acc]
      end

    collect_distinct_nodes(ring, idx + 1, size, n, new_acc, steps + 1)
  end

  defp replication_factor do
    Application.get_env(:kvstore, :replication_factor, 3)
  end
end
