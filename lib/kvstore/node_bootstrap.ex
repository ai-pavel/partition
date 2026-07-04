defmodule KVStore.NodeBootstrap do
  @moduledoc """
  Bootstraps initial storage nodes on application start.

  Starts a configurable number of local GenServer nodes and registers
  them in the consistent hash ring.
  """
  use GenServer

  alias KVStore.{Ring, Node}

  @default_node_count 3

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Start the node registry first if it doesn't exist
    ensure_registry()

    node_count = @default_node_count

    node_ids =
      for i <- 1..node_count do
        node_id = :"node_#{i}"
        {:ok, _pid} = DynamicSupervisor.start_child(KVStore.NodeSupervisor, {Node, node_id})
        Ring.add_node(node_id)
        node_id
      end

    {:ok, %{node_ids: node_ids}}
  end

  defp ensure_registry do
    case Registry.start_link(keys: :unique, name: KVStore.NodeRegistry) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
  end
end
