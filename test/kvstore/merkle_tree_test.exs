defmodule KVStore.MerkleTreeTest do
  use ExUnit.Case, async: true

  alias KVStore.MerkleTree

  test "empty tree has a zero root hash" do
    tree = MerkleTree.build([])
    assert MerkleTree.root_hash(tree) == <<0::256>>
  end

  test "single leaf tree has root equal to that leaf's hash" do
    hash = :crypto.hash(:sha256, "value1")
    tree = MerkleTree.build([{"key1", hash}])
    assert MerkleTree.root_hash(tree) == hash
  end

  test "identical data produces identical root hashes" do
    leaves = [
      {"a", :crypto.hash(:sha256, "1")},
      {"b", :crypto.hash(:sha256, "2")},
      {"c", :crypto.hash(:sha256, "3")}
    ]

    tree1 = MerkleTree.build(leaves)
    tree2 = MerkleTree.build(leaves)
    assert MerkleTree.root_hash(tree1) == MerkleTree.root_hash(tree2)
  end

  test "different data produces different root hashes" do
    leaves_a = [
      {"a", :crypto.hash(:sha256, "1")},
      {"b", :crypto.hash(:sha256, "2")}
    ]

    leaves_b = [
      {"a", :crypto.hash(:sha256, "1")},
      {"b", :crypto.hash(:sha256, "CHANGED")}
    ]

    tree_a = MerkleTree.build(leaves_a)
    tree_b = MerkleTree.build(leaves_b)
    assert MerkleTree.root_hash(tree_a) != MerkleTree.root_hash(tree_b)
  end

  test "diff of identical trees returns empty list" do
    leaves = [{"a", :crypto.hash(:sha256, "1")}, {"b", :crypto.hash(:sha256, "2")}]
    tree = MerkleTree.build(leaves)
    assert MerkleTree.diff(tree, tree) == []
  end

  test "diff finds changed keys" do
    tree_a =
      MerkleTree.build([
        {"a", :crypto.hash(:sha256, "1")},
        {"b", :crypto.hash(:sha256, "2")}
      ])

    tree_b =
      MerkleTree.build([
        {"a", :crypto.hash(:sha256, "1")},
        {"b", :crypto.hash(:sha256, "CHANGED")}
      ])

    assert "b" in MerkleTree.diff(tree_a, tree_b)
  end

  test "diff of empty vs non-empty returns all keys" do
    tree_a = MerkleTree.build([])

    tree_b =
      MerkleTree.build([
        {"x", :crypto.hash(:sha256, "1")},
        {"y", :crypto.hash(:sha256, "2")}
      ])

    diff = MerkleTree.diff(tree_a, tree_b)
    assert "x" in diff
    assert "y" in diff
  end
end
