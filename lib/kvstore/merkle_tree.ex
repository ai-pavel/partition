defmodule KVStore.MerkleTree do
  @moduledoc """
  A simple binary Merkle tree for comparing data sets between replicas.

  The tree is built from a sorted list of `{key, hash}` leaf pairs.
  Internal nodes store the SHA-256 hash of their children's concatenated
  hashes. Two replicas can compare root hashes and then drill down to
  find exactly which keys differ.
  """

  defstruct [:root]

  @type hash :: binary()
  @type leaf :: {String.t(), hash()}
  @type tree_node ::
          {:leaf, String.t(), hash()}
          | {:node, hash(), tree_node(), tree_node()}
          | :empty

  @type t :: %__MODULE__{root: tree_node()}

  @doc "Builds a Merkle tree from a sorted list of {key, hash} pairs."
  @spec build([leaf()]) :: t()
  def build([]), do: %__MODULE__{root: :empty}

  def build(leaves) do
    nodes = Enum.map(leaves, fn {key, hash} -> {:leaf, key, hash} end)
    %__MODULE__{root: build_tree(nodes)}
  end

  @doc "Returns the root hash of the tree."
  @spec root_hash(t() | nil) :: hash()
  def root_hash(nil), do: <<0::256>>
  def root_hash(%__MODULE__{root: :empty}), do: <<0::256>>
  def root_hash(%__MODULE__{root: root}), do: node_hash(root)

  @doc """
  Compares two Merkle trees and returns the list of keys that differ
  (present in one but not the other, or with different hashes).
  """
  @spec diff(t(), t()) :: [String.t()]
  def diff(%__MODULE__{root: a}, %__MODULE__{root: b}) do
    diff_nodes(a, b) |> Enum.uniq() |> Enum.sort()
  end

  ## Internal

  defp build_tree([single]), do: single

  defp build_tree(nodes) do
    nodes
    |> Enum.chunk_every(2)
    |> Enum.map(fn
      [left, right] ->
        h = hash_pair(node_hash(left), node_hash(right))
        {:node, h, left, right}

      [left] ->
        left
    end)
    |> build_tree()
  end

  defp node_hash({:leaf, _key, hash}), do: hash
  defp node_hash({:node, hash, _l, _r}), do: hash
  defp node_hash(:empty), do: <<0::256>>

  defp hash_pair(a, b) do
    :crypto.hash(:sha256, a <> b)
  end

  defp diff_nodes(:empty, :empty), do: []
  defp diff_nodes(:empty, other), do: collect_keys(other)
  defp diff_nodes(other, :empty), do: collect_keys(other)

  defp diff_nodes(a, b) do
    if node_hash(a) == node_hash(b) do
      []
    else
      case {a, b} do
        {{:leaf, key_a, _}, {:leaf, key_b, _}} ->
          if key_a == key_b, do: [key_a], else: [key_a, key_b]

        {{:node, _, la, ra}, {:node, _, lb, rb}} ->
          diff_nodes(la, lb) ++ diff_nodes(ra, rb)

        {{:leaf, key, _}, {:node, _, _, _}} ->
          [key | collect_keys(b)]

        {{:node, _, _, _}, {:leaf, key, _}} ->
          collect_keys(a) ++ [key]
      end
    end
  end

  defp collect_keys(:empty), do: []
  defp collect_keys({:leaf, key, _}), do: [key]
  defp collect_keys({:node, _, left, right}), do: collect_keys(left) ++ collect_keys(right)
end
