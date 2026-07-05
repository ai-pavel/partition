defmodule KVStoreFaultToleranceTest do
  use ExUnit.Case, async: false

  alias KVStore.Node

  # A single downed replica must be survivable: get/put should degrade
  # gracefully rather than crash the caller with a GenServer :exit.

  test "put and get still succeed when one replica in the preference list is down" do
    key = "fault_#{:erlang.unique_integer([:positive])}"
    nodes = KVStore.Ring.preference_list(key)

    if length(nodes) >= 2 do
      # Stop the first replica the request would touch.
      [down | _rest] = nodes

      case Registry.lookup(KVStore.NodeRegistry, down) do
        [{pid, _}] ->
          try do
            GenServer.stop(pid)
          catch
            :exit, _ -> :ok
          end

        [] ->
          :ok
      end

      # put must not crash and must succeed via a surviving replica.
      assert :ok = KVStore.put(key, "survives", timestamp: System.os_time(:microsecond))

      # get must not crash and must return the value from a surviving replica.
      assert {:ok, "survives"} = KVStore.get(key)
    end
  end
end
