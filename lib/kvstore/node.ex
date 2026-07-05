defmodule KVStore.Node do
  @moduledoc """
  A storage node GenServer.

  Each node holds a partition of the key-value data in an ETS table.
  Values are stored as LWW-Registers so that concurrent writes are
  resolved deterministically. The node also maintains a Merkle tree
  digest of its data for efficient anti-entropy synchronisation.
  """
  use GenServer

  alias KVStore.CRDT.LWWRegister
  alias KVStore.MerkleTree

  @type node_id :: atom()

  ## Client API

  @doc "Starts a named storage node."
  @spec start_link(node_id()) :: GenServer.on_start()
  def start_link(node_id) do
    GenServer.start_link(__MODULE__, node_id, name: via(node_id))
  end

  @doc "Stores a key/value pair with the given timestamp."
  @spec put(node_id(), String.t(), term(), integer()) :: :ok | {:error, term()}
  def put(node_id, key, value, timestamp) do
    GenServer.call(via(node_id), {:put, key, value, timestamp})
  end

  @doc "Retrieves the LWW register for a key."
  @spec get(node_id(), String.t()) :: {:ok, LWWRegister.t()} | {:error, :not_found}
  def get(node_id, key) do
    GenServer.call(via(node_id), {:get, key})
  end

  @doc "Returns all key-register pairs (used during sync)."
  @spec all_data(node_id()) :: [{String.t(), LWWRegister.t()}]
  def all_data(node_id) do
    GenServer.call(via(node_id), :all_data)
  end

  @doc "Merges a batch of key-register pairs into this node (anti-entropy)."
  @spec merge_data(node_id(), [{String.t(), LWWRegister.t()}]) :: :ok
  def merge_data(node_id, entries) do
    GenServer.call(via(node_id), {:merge_data, entries})
  end

  @doc "Returns the Merkle tree root hash for the node's data."
  @spec merkle_root(node_id()) :: binary()
  def merkle_root(node_id) do
    GenServer.call(via(node_id), :merkle_root)
  end

  @doc "Returns the full Merkle tree for the node's data."
  @spec merkle_tree(node_id()) :: MerkleTree.t()
  def merkle_tree(node_id) do
    GenServer.call(via(node_id), :merkle_tree)
  end

  @doc "Checks if a node process is alive."
  @spec alive?(node_id()) :: boolean()
  def alive?(node_id) do
    case Registry.lookup(KVStore.NodeRegistry, node_id) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  ## Server Callbacks

  @impl true
  def init(node_id) do
    table = :ets.new(:"kvstore_#{node_id}", [:set, :protected])

    {:ok,
     %{
       node_id: node_id,
       table: table,
       merkle_dirty: true,
       merkle_cache: nil
     }}
  end

  @impl true
  def handle_call({:put, key, value, timestamp}, _from, state) do
    new_reg = LWWRegister.new(value, timestamp)

    case :ets.lookup(state.table, key) do
      [{^key, existing}] ->
        merged = LWWRegister.merge(existing, new_reg)
        :ets.insert(state.table, {key, merged})

      [] ->
        :ets.insert(state.table, {key, new_reg})
    end

    {:reply, :ok, %{state | merkle_dirty: true}}
  end

  def handle_call({:get, key}, _from, state) do
    result =
      case :ets.lookup(state.table, key) do
        [{^key, register}] -> {:ok, register}
        [] -> {:error, :not_found}
      end

    {:reply, result, state}
  end

  def handle_call(:all_data, _from, state) do
    data = :ets.tab2list(state.table)
    {:reply, data, state}
  end

  def handle_call({:merge_data, entries}, _from, state) do
    Enum.each(entries, fn {key, remote_reg} ->
      case :ets.lookup(state.table, key) do
        [{^key, local_reg}] ->
          merged = LWWRegister.merge(local_reg, remote_reg)
          :ets.insert(state.table, {key, merged})

        [] ->
          :ets.insert(state.table, {key, remote_reg})
      end
    end)

    {:reply, :ok, %{state | merkle_dirty: true}}
  end

  def handle_call(:merkle_root, _from, state) do
    state = maybe_rebuild_merkle(state)
    {:reply, MerkleTree.root_hash(state.merkle_cache), state}
  end

  def handle_call(:merkle_tree, _from, state) do
    state = maybe_rebuild_merkle(state)
    {:reply, state.merkle_cache, state}
  end

  ## Internal

  defp maybe_rebuild_merkle(%{merkle_dirty: false} = state), do: state

  defp maybe_rebuild_merkle(state) do
    data = :ets.tab2list(state.table)

    leaves =
      Enum.map(data, fn {key, %LWWRegister{value: v, timestamp: ts}} ->
        {key, :crypto.hash(:sha256, :erlang.term_to_binary({v, ts}))}
      end)
      |> Enum.sort_by(fn {k, _} -> k end)

    tree = MerkleTree.build(leaves)
    %{state | merkle_cache: tree, merkle_dirty: false}
  end

  defp via(node_id) do
    {:via, Registry, {KVStore.NodeRegistry, node_id}}
  end
end
