defmodule KVStore.NodeTest do
  use ExUnit.Case, async: false

  alias KVStore.Node
  alias KVStore.CRDT.LWWRegister

  setup do
    # Ensure registry exists
    case Registry.start_link(keys: :unique, name: KVStore.NodeRegistry) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    node_id = :"test_node_#{:erlang.unique_integer([:positive])}"
    {:ok, pid} = Node.start_link(node_id)

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    {:ok, node_id: node_id}
  end

  test "put and get a value", %{node_id: node_id} do
    :ok = Node.put(node_id, "key1", "value1", 1000)
    {:ok, reg} = Node.get(node_id, "key1")
    assert reg.value == "value1"
    assert reg.timestamp == 1000
  end

  test "get returns error for missing key", %{node_id: node_id} do
    assert {:error, :not_found} = Node.get(node_id, "nonexistent")
  end

  test "put merges with existing value using LWW", %{node_id: node_id} do
    :ok = Node.put(node_id, "key1", "old", 100)
    :ok = Node.put(node_id, "key1", "new", 200)
    {:ok, reg} = Node.get(node_id, "key1")
    assert reg.value == "new"
  end

  test "older write does not overwrite newer value", %{node_id: node_id} do
    :ok = Node.put(node_id, "key1", "new", 200)
    :ok = Node.put(node_id, "key1", "old", 100)
    {:ok, reg} = Node.get(node_id, "key1")
    assert reg.value == "new"
  end

  test "all_data returns all stored entries", %{node_id: node_id} do
    :ok = Node.put(node_id, "a", 1, 100)
    :ok = Node.put(node_id, "b", 2, 200)
    data = Node.all_data(node_id)
    keys = Enum.map(data, fn {k, _v} -> k end) |> Enum.sort()
    assert keys == ["a", "b"]
  end

  test "merge_data incorporates remote entries", %{node_id: node_id} do
    :ok = Node.put(node_id, "local", "val", 100)

    remote_entry = {"remote_key", LWWRegister.new("remote_val", 200)}
    :ok = Node.merge_data(node_id, [remote_entry])

    {:ok, reg} = Node.get(node_id, "remote_key")
    assert reg.value == "remote_val"
  end

  test "merge_data resolves conflicts via LWW", %{node_id: node_id} do
    :ok = Node.put(node_id, "shared", "local_new", 300)

    remote_entry = {"shared", LWWRegister.new("remote_old", 100)}
    :ok = Node.merge_data(node_id, [remote_entry])

    {:ok, reg} = Node.get(node_id, "shared")
    assert reg.value == "local_new"
  end

  test "merkle_root changes when data changes", %{node_id: node_id} do
    root1 = Node.merkle_root(node_id)
    :ok = Node.put(node_id, "x", "y", 100)
    root2 = Node.merkle_root(node_id)
    assert root1 != root2
  end
end
