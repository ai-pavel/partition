defmodule KVStore.CRDTTest do
  use ExUnit.Case, async: true

  alias KVStore.CRDT.{LWWRegister, GCounter}

  # ---------------------------------------------------------------------------
  # LWW-Register
  # ---------------------------------------------------------------------------

  describe "LWWRegister" do
    test "new/2 creates a register with value and timestamp" do
      reg = LWWRegister.new("hello", 100)
      assert reg.value == "hello"
      assert reg.timestamp == 100
    end

    test "update/3 accepts a newer timestamp" do
      reg = LWWRegister.new("old", 100)
      updated = LWWRegister.update(reg, "new", 200)
      assert updated.value == "new"
      assert updated.timestamp == 200
    end

    test "update/3 rejects an older timestamp" do
      reg = LWWRegister.new("current", 200)
      same = LWWRegister.update(reg, "old_write", 100)
      assert same.value == "current"
      assert same.timestamp == 200
    end

    test "merge/2 keeps the register with the higher timestamp" do
      a = LWWRegister.new("a_val", 100)
      b = LWWRegister.new("b_val", 200)

      assert LWWRegister.merge(a, b).value == "b_val"
      assert LWWRegister.merge(b, a).value == "b_val"
    end

    test "merge/2 is commutative" do
      a = LWWRegister.new("x", 100)
      b = LWWRegister.new("y", 200)

      assert LWWRegister.merge(a, b) == LWWRegister.merge(b, a)
    end

    test "merge/2 is idempotent" do
      a = LWWRegister.new("x", 100)
      assert LWWRegister.merge(a, a) == a
    end

    test "merge/2 handles equal timestamps deterministically" do
      a = LWWRegister.new("alpha", 100)
      b = LWWRegister.new("beta", 100)

      result1 = LWWRegister.merge(a, b)
      result2 = LWWRegister.merge(b, a)
      assert result1.value == result2.value
    end
  end

  # ---------------------------------------------------------------------------
  # G-Counter
  # ---------------------------------------------------------------------------

  describe "GCounter" do
    test "new counter has value 0" do
      assert GCounter.value(GCounter.new()) == 0
    end

    test "increment increases the value" do
      counter =
        GCounter.new()
        |> GCounter.increment(:node_a)
        |> GCounter.increment(:node_a)
        |> GCounter.increment(:node_b, 3)

      assert GCounter.value(counter) == 5
    end

    test "merge takes the max of each node's count" do
      a =
        GCounter.new()
        |> GCounter.increment(:node_a, 5)
        |> GCounter.increment(:node_b, 2)

      b =
        GCounter.new()
        |> GCounter.increment(:node_a, 3)
        |> GCounter.increment(:node_b, 7)
        |> GCounter.increment(:node_c, 1)

      merged = GCounter.merge(a, b)
      assert GCounter.value(merged) == 5 + 7 + 1
    end

    test "merge is commutative" do
      a = GCounter.new() |> GCounter.increment(:x, 3)
      b = GCounter.new() |> GCounter.increment(:y, 5)

      assert GCounter.merge(a, b) == GCounter.merge(b, a)
    end

    test "merge is idempotent" do
      a = GCounter.new() |> GCounter.increment(:x, 3)
      assert GCounter.merge(a, a) == a
    end

    test "merge is associative" do
      a = GCounter.new() |> GCounter.increment(:x, 1)
      b = GCounter.new() |> GCounter.increment(:y, 2)
      c = GCounter.new() |> GCounter.increment(:z, 3)

      left = GCounter.merge(GCounter.merge(a, b), c)
      right = GCounter.merge(a, GCounter.merge(b, c))
      assert left == right
    end
  end
end
