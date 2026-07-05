defmodule KVStoreTest do
  use ExUnit.Case, async: false

  alias KVStore.Node
  alias KVStore.CRDT.LWWRegister

  # The application already starts the Ring, sync, and bootstrapped nodes.
  # These tests focus on the read path's conflict resolution, so they write
  # directly to the replica nodes that `KVStore.get/2` will read from.

  test "get resolves equal-timestamp conflicts the same way LWWRegister.merge does" do
    key = "conflict_read_#{:erlang.unique_integer([:positive])}"
    nodes = KVStore.Ring.preference_list(key)

    # Need at least two replicas to create a conflicting read.
    if length(nodes) >= 2 do
      ts = System.os_time(:microsecond)

      value_a = "alpha"
      value_b = "beta"

      [node_a, node_b | _] = nodes
      :ok = Node.put(node_a, key, value_a, ts)
      :ok = Node.put(node_b, key, value_b, ts)

      # The value the merge/convergence path would settle on.
      expected =
        LWWRegister.merge(LWWRegister.new(value_a, ts), LWWRegister.new(value_b, ts)).value

      assert {:ok, ^expected} = KVStore.get(key)
    end
  end
end
