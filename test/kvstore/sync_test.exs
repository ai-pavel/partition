defmodule KVStore.SyncTest do
  use ExUnit.Case, async: false

  alias KVStore.{Ring, Node, Sync}
  alias KVStore.CRDT.LWWRegister

  setup do
    # Ensure registry
    case Registry.start_link(keys: :unique, name: KVStore.NodeRegistry) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    # Stop existing processes if running
    for name <- [Ring, Sync] do
      if Process.whereis(name), do: GenServer.stop(name)
    end

    {:ok, _} = Ring.start_link([])
    {:ok, _} = Sync.start_link([])

    # Start two test nodes
    node_a = :"sync_a_#{:erlang.unique_integer([:positive])}"
    node_b = :"sync_b_#{:erlang.unique_integer([:positive])}"

    {:ok, pid_a} = Node.start_link(node_a)
    {:ok, pid_b} = Node.start_link(node_b)

    Ring.add_node(node_a)
    Ring.add_node(node_b)

    on_exit(fn ->
      if Process.alive?(pid_a), do: GenServer.stop(pid_a)
      if Process.alive?(pid_b), do: GenServer.stop(pid_b)
      if Process.whereis(Ring), do: GenServer.stop(Ring)
      if Process.whereis(Sync), do: GenServer.stop(Sync)
    end)

    {:ok, node_a: node_a, node_b: node_b}
  end

  test "sync propagates data between nodes", %{node_a: node_a, node_b: node_b} do
    # Write to node_a only
    :ok = Node.put(node_a, "sync_key", "sync_val", 1000)

    # node_b should not have it yet
    assert {:error, :not_found} = Node.get(node_b, "sync_key")

    # Trigger sync
    Sync.sync_now()

    # Now node_b should have the data
    {:ok, reg} = Node.get(node_b, "sync_key")
    assert reg.value == "sync_val"
  end

  test "sync resolves conflicts using LWW merge", %{node_a: node_a, node_b: node_b} do
    # Write different values to same key on both nodes
    :ok = Node.put(node_a, "conflict", "old_a", 100)
    :ok = Node.put(node_b, "conflict", "new_b", 200)

    Sync.sync_now()

    # Both should now have the newer value
    {:ok, reg_a} = Node.get(node_a, "conflict")
    {:ok, reg_b} = Node.get(node_b, "conflict")

    assert reg_a.value == "new_b"
    assert reg_b.value == "new_b"
  end

  test "sync is idempotent", %{node_a: node_a, node_b: node_b} do
    :ok = Node.put(node_a, "idem", "val", 100)
    Sync.sync_now()
    Sync.sync_now()
    Sync.sync_now()

    {:ok, reg} = Node.get(node_b, "idem")
    assert reg.value == "val"
  end
end
