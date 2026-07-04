defmodule KVStore.CRDT do
  @moduledoc """
  Conflict-free Replicated Data Types (CRDTs) for the distributed store.

  Implements:
  - **LWW-Register** (Last-Writer-Wins Register): resolves conflicts by
    keeping the value with the highest timestamp.
  - **G-Counter** (Grow-only Counter): a distributed counter that can only
    be incremented, with per-node counts merged via max.
  """

  # ---------------------------------------------------------------------------
  # LWW-Register
  # ---------------------------------------------------------------------------

  defmodule LWWRegister do
    @moduledoc """
    A Last-Writer-Wins Register.

    Each write is tagged with a timestamp. On merge, the value with the
    higher timestamp wins. Ties are broken by comparing values with `>=/2`.
    """
    @enforce_keys [:value, :timestamp]
    defstruct [:value, :timestamp]

    @type t :: %__MODULE__{
            value: term(),
            timestamp: integer()
          }

    @doc "Creates a new LWW register."
    @spec new(term(), integer()) :: t()
    def new(value, timestamp \\ System.os_time(:microsecond)) do
      %__MODULE__{value: value, timestamp: timestamp}
    end

    @doc "Updates the register if the new timestamp is more recent."
    @spec update(t(), term(), integer()) :: t()
    def update(%__MODULE__{timestamp: old_ts} = reg, value, timestamp) do
      if timestamp > old_ts do
        %__MODULE__{value: value, timestamp: timestamp}
      else
        reg
      end
    end

    @doc "Merges two registers, keeping the one with the higher timestamp."
    @spec merge(t(), t()) :: t()
    def merge(%__MODULE__{timestamp: ts1} = a, %__MODULE__{timestamp: ts2} = b) do
      cond do
        ts1 > ts2 -> a
        ts2 > ts1 -> b
        # Tie-break: compare values deterministically
        true -> if inspect(a.value) >= inspect(b.value), do: a, else: b
      end
    end
  end

  # ---------------------------------------------------------------------------
  # G-Counter
  # ---------------------------------------------------------------------------

  defmodule GCounter do
    @moduledoc """
    A Grow-only Counter.

    Each node maintains its own count. The total value is the sum of all
    per-node counts. Merge takes the max of each node's count.
    """
    defstruct counts: %{}

    @type t :: %__MODULE__{
            counts: %{atom() => non_neg_integer()}
          }

    @doc "Creates a new empty G-Counter."
    @spec new() :: t()
    def new, do: %__MODULE__{counts: %{}}

    @doc "Increments the counter for the given node by `amount` (default 1)."
    @spec increment(t(), atom(), pos_integer()) :: t()
    def increment(%__MODULE__{counts: counts} = counter, node_id, amount \\ 1) do
      new_counts = Map.update(counts, node_id, amount, &(&1 + amount))
      %{counter | counts: new_counts}
    end

    @doc "Returns the total value of the counter (sum of all node counts)."
    @spec value(t()) :: non_neg_integer()
    def value(%__MODULE__{counts: counts}) do
      counts |> Map.values() |> Enum.sum()
    end

    @doc "Merges two G-Counters by taking the max count for each node."
    @spec merge(t(), t()) :: t()
    def merge(%__MODULE__{counts: a}, %__MODULE__{counts: b}) do
      merged =
        Map.merge(a, b, fn _node, count_a, count_b ->
          max(count_a, count_b)
        end)

      %__MODULE__{counts: merged}
    end
  end
end
