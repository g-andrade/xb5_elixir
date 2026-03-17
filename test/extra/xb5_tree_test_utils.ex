defmodule Xb5TreeTestUtils do
  @moduledoc """
  Test helpers specific to `Xb5.Tree`. Translated from the per-suite helpers in
  `xb5_trees_test_SUITE.erl` that are tree-specific (unique key-value generation,
  second-tree generation with overlap variants, sequential boundary trees).
  """

  import ExUnit.Assertions

  # -------------------------------------------------------------------------
  # Ref-kv and tree construction
  # -------------------------------------------------------------------------

  @doc """
  Generates `size` `{key, value}` pairs with unique keys (unique by `==`).
  Values are tagged tuples `{:initial_value_for, key}`. Result is key-sorted.
  """
  def new_ref_kvs(size) do
    new_ref_kvs_recur(size, [])
  end

  defp new_ref_kvs_recur(0, acc), do: :lists.keysort(1, acc)

  defp new_ref_kvs_recur(remaining, acc) do
    key = Xb5TestUtils.new_element()

    if Enum.any?(acc, fn {k, _} -> k == key end) do
      new_ref_kvs_recur(remaining, acc)
    else
      new_ref_kvs_recur(remaining - 1, [{key, {:initial_value_for, key}} | acc])
    end
  end

  @doc """
  Builds an `Xb5.Tree` by calling `put/3` for each `{key, value}` pair in `list`.

  Also asserts the initial empty tree has size 0 (mirrors the Erlang suite's
  assertion inside this helper).
  """
  def new_tree_from_each_inserted(list) do
    tree = Xb5.Tree.new()
    assert Xb5.Tree.size(tree) == 0
    Enum.reduce(list, tree, fn {key, value}, acc -> Xb5.Tree.put(acc, key, value) end)
  end

  @doc """
  Returns `list` unchanged 2/3 of the time; shuffled 1/3 of the time.

  Sequential and random insertion take very different tree paths — the
  occasional shuffle gives better coverage of both.
  """
  def maybe_shuffle_for_new_tree(list) do
    if :rand.uniform() < 1 / 3 do
      Xb5TestUtils.list_shuffle(list)
    else
      list
    end
  end

  # -------------------------------------------------------------------------
  # Size + ref-kv iteration
  # -------------------------------------------------------------------------

  @doc """
  Calls `fun.(size, ref_kvs)` for 200 diverse sizes.

  A freshly generated sorted list of unique-key pairs is produced for each size.
  """
  def foreach_tested_size(fun) do
    Xb5TestUtils.foreach_tested_size(fn size ->
      ref_kvs = new_ref_kvs(size)
      fun.(size, ref_kvs)
    end)
  end

  @doc """
  Calls `fun.(size, ref_kvs, tree)` for 200 diverse sizes.

  The tree is built by inserting the ref kvs (possibly shuffled).
  """
  def foreach_test_tree(fun) do
    foreach_tested_size(fn size, ref_kvs ->
      tree = new_tree_from_each_inserted(maybe_shuffle_for_new_tree(ref_kvs))
      assert Xb5.Tree.size(tree) == size
      fun.(size, ref_kvs, tree)
    end)
  end

  # -------------------------------------------------------------------------
  # Second-tree generation
  # -------------------------------------------------------------------------

  @doc """
  Generates partner trees and calls `fun.(ref_kvs2, tree2)` for a range of
  size and overlap combinations.

  Options:
  - `:test_variants2` — also test sequential "all before"/"all after" trees
  - `:max_combos` — limit the number of param combinations tried (default: all)
  """
  def foreach_second_tree(fun, size, ref_kvs, opts \\ []) do
    foreach_second_tree_variants1(fun, size, ref_kvs, opts)

    if Keyword.get(opts, :test_variants2, false) do
      foreach_second_tree_variants2(fun, size, ref_kvs)
    end

    :ok
  end

  defp foreach_second_tree_variants1(fun, size, ref_kvs, opts) do
    amounts2 =
      :lists.usort([
        0,
        1,
        size,
        :rand.uniform(max(1, size)),
        :rand.uniform(size + 100)
      ])

    percentages_in_common = [0.0, 0.5, 0.8, 1.0]

    param_combos =
      for amount2 <- amounts2, pct <- percentages_in_common, do: {amount2, pct}

    max_combos = Keyword.get(opts, :max_combos, length(param_combos))

    param_combos
    |> Xb5TestUtils.list_shuffle()
    |> Enum.take(max_combos)
    |> Enum.each(fn {amount2, pct_in_common} ->
      repeated_amount = floor(pct_in_common * min(amount2, size))
      new_amount = amount2 - repeated_amount

      repeated_kvs =
        ref_kvs
        |> Xb5TestUtils.list_shuffle()
        |> Enum.take(repeated_amount)

      new_kvs =
        for _ <- 1..new_amount//1 do
          key = Xb5TestUtils.new_element()
          {key, {:value2_for, key}}
        end

      ref_kvs2 =
        repeated_kvs
        |> Kernel.++(new_kvs)
        |> :lists.usort()
        |> then(fn list -> :lists.ukeysort(1, list) end)
        |> Enum.map(&randomly_switch_key_type/1)

      tree2 = Xb5.Tree.new(maybe_shuffle_for_new_tree(ref_kvs2))

      fun.(ref_kvs2, tree2)
    end)
  end

  defp foreach_second_tree_variants2(fun, size, ref_kvs) do
    amounts2 = Enum.filter(:lists.usort([0, 1, size - 1, size + 1]), &(&1 >= 0))

    for placement <- [:before, :after_], amount2 <- amounts2 do
      ref_kvs2 = sequential_ref_kvs(placement, amount2, ref_kvs)
      tree2 = Xb5.Tree.new(ref_kvs2)
      fun.(ref_kvs2, tree2)
    end
  end

  defp sequential_ref_kvs(_placement, 0, _ref_kvs), do: []
  defp sequential_ref_kvs(_placement, _size, []), do: []

  defp sequential_ref_kvs(:before, size, ref_kvs) do
    {first_key, _} = hd(ref_kvs)
    sequential_ref_kvs_before(size, first_key, [])
  end

  defp sequential_ref_kvs(:after_, size, ref_kvs) do
    {last_key, _} = List.last(ref_kvs)
    sequential_ref_kvs_after(size, last_key)
  end

  defp sequential_ref_kvs_before(0, _next_key, acc), do: acc

  defp sequential_ref_kvs_before(size, next_key, acc) do
    smaller_key = Xb5TestUtils.element_smaller(next_key)
    assert smaller_key < next_key
    sequential_ref_kvs_before(size - 1, smaller_key, [{smaller_key, :value2} | acc])
  end

  defp sequential_ref_kvs_after(0, _prev_key), do: []

  defp sequential_ref_kvs_after(size, prev_key) do
    larger_key = Xb5TestUtils.element_larger(prev_key)
    assert larger_key > prev_key
    [{larger_key, :value2} | sequential_ref_kvs_after(size - 1, larger_key)]
  end

  # -------------------------------------------------------------------------
  # Key helpers
  # -------------------------------------------------------------------------

  @doc """
  Normalises a key for comparison: whole-number floats become integers,
  composite types are normalised recursively.
  """
  def canon_key(key), do: Xb5TestUtils.canon_element(key)

  @doc """
  Normalises a list of `{key, value}` pairs: each key is passed through
  `canon_key/1`. Values are left untouched.
  """
  def canon_kvs(kvs), do: Enum.map(kvs, fn {k, v} -> {canon_key(k), v} end)

  @doc """
  Applies `randomly_switch_number_type/1` to the key portion of `{key, value}`.
  """
  def randomly_switch_key_type({key, value}) do
    {Xb5TestUtils.randomly_switch_number_type(key), value}
  end

  # -------------------------------------------------------------------------
  # Sorted-list helpers (key-value aware)
  # -------------------------------------------------------------------------

  @doc "Inserts `{key, value}` into a key-sorted list, preserving order."
  def add_to_sorted_list(key, value, [{hk, _} = h | t]) do
    if key > hk, do: [h | add_to_sorted_list(key, value, t)], else: [{key, value}, h | t]
  end

  def add_to_sorted_list(key, value, []), do: [{key, value}]

  @doc "Removes the first `{k, v}` pair where `k == key` from a key-sorted list."
  def remove_from_sorted_list(key, [{hk, _} = h | t]) do
    cond do
      key > hk -> [h | remove_from_sorted_list(key, t)]
      key == hk -> t
    end
  end

  @doc "Updates the value for `key` in a key-sorted list."
  def update_in_sorted_list(key, value, [{hk, _} = h | t]) do
    cond do
      key > hk -> [h | update_in_sorted_list(key, value, t)]
      key == hk -> [{key, value} | t]
    end
  end
end
