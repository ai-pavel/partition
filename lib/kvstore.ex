defmodule KVStore do
  @moduledoc """
  A distributed key-value store built on OTP with consistent hashing,
  CRDT-based conflict resolution, and Merkle-tree anti-entropy sync.

  ## Public API

      KVStore.put("users:1", %{name: "Alice"})
      KVStore.get("users:1")
      KVStore.delete("users:1")
  """

  alias KVStore.{Ring, Node}

  @doc """
  Stores a value under the given key, replicating to N nodes determined
  by the consistent hash ring.
  """
  @spec put(String.t(), term(), keyword()) :: :ok | {:error, term()}
  def put(key, value, opts \\ []) do
    nodes = Ring.preference_list(key)
    timestamp = Keyword.get(opts, :timestamp, System.os_time(:microsecond))

    results =
      Enum.map(nodes, fn node_id ->
        Node.put(node_id, key, value, timestamp)
      end)

    case Enum.find(results, &match?(:ok, &1)) do
      :ok -> :ok
      nil -> {:error, :all_nodes_failed}
    end
  end

  @doc """
  Retrieves the value for the given key. Reads from all replica nodes and
  returns the most recent value (last-writer-wins).
  """
  @spec get(String.t(), keyword()) :: {:ok, term()} | {:error, :not_found}
  def get(key, _opts \\ []) do
    nodes = Ring.preference_list(key)

    results =
      nodes
      |> Enum.map(fn node_id -> Node.get(node_id, key) end)
      |> Enum.reject(&match?({:error, _}, &1))

    case results do
      [] ->
        {:error, :not_found}

      values ->
        # Return the value with the highest timestamp (LWW)
        {_ts, value} =
          values
          |> Enum.map(fn {:ok, lww} -> {lww.timestamp, lww.value} end)
          |> Enum.max_by(fn {ts, _v} -> ts end)

        if value == :__tombstone__ do
          {:error, :not_found}
        else
          {:ok, value}
        end
    end
  end

  @doc """
  Deletes a key by writing a tombstone with the current timestamp.
  """
  @spec delete(String.t(), keyword()) :: :ok | {:error, term()}
  def delete(key, opts \\ []) do
    put(key, :__tombstone__, opts)
  end
end
