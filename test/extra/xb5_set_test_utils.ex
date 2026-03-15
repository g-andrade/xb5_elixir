defmodule Xb5SetTestUtils do
  @moduledoc """
  Test helpers specific to `Xb5.Set`. Translated from the per-suite helpers in
  `xb5_sets_test_SUITE.erl` that are set-specific (unique element generation,
  second-set generation with overlap variants, sequential boundary sets).
  """

  import ExUnit.Assertions

  # -------------------------------------------------------------------------
  # Ref-element and set construction
  # -------------------------------------------------------------------------

  @doc """
  Generates `size` elements unique by `==`, sorted in ascending term order.
  """
  def new_ref_elements(size) do
    new_ref_elements_recur(size, [])
  end

  defp new_ref_elements_recur(0, acc), do: :lists.sort(acc)

  defp new_ref_elements_recur(remaining, acc) do
    elem = Xb5TestUtils.new_element()

    if Enum.any?(acc, &(&1 == elem)) do
      new_ref_elements_recur(remaining, acc)
    else
      new_ref_elements_recur(remaining - 1, [elem | acc])
    end
  end

  @doc """
  Builds an `Xb5.Set` by calling `put/2` for each element in `list`.

  Also asserts the initial empty set has size 0 (mirrors the Erlang suite's
  assertion inside this helper).
  """
  def new_set_from_each_inserted(list) do
    set = Xb5.Set.new()
    assert Xb5.Set.size(set) == 0
    Enum.reduce(list, set, fn elem, acc -> Xb5.Set.put(acc, elem) end)
  end

  @doc """
  Returns `list` unchanged 2/3 of the time; shuffled 1/3 of the time.

  Sequential and random insertion take very different tree paths — the
  occasional shuffle gives better coverage of both.
  """
  def maybe_shuffle_for_new_set(list) do
    if :rand.uniform() < 1 / 3 do
      Xb5TestUtils.list_shuffle(list)
    else
      list
    end
  end

  # -------------------------------------------------------------------------
  # Size + ref-element iteration
  # -------------------------------------------------------------------------

  @doc """
  Calls `fun.(size, ref_elements)` for 200 diverse sizes.

  A freshly generated sorted list of unique elements is produced for each size.
  """
  def foreach_tested_size(fun) do
    Xb5TestUtils.foreach_tested_size(fn size ->
      ref_elements = new_ref_elements(size)
      fun.(size, ref_elements)
    end)
  end

  @doc """
  Calls `fun.(size, ref_elements, set)` for 200 diverse sizes.

  The set is built by inserting the ref elements (possibly shuffled).
  """
  def foreach_test_set(fun) do
    foreach_tested_size(fn size, ref_elements ->
      set = new_set_from_each_inserted(maybe_shuffle_for_new_set(ref_elements))
      assert Xb5.Set.size(set) == size
      fun.(size, ref_elements, set)
    end)
  end

  # -------------------------------------------------------------------------
  # Second-set generation
  # -------------------------------------------------------------------------

  @doc """
  Generates partner sets and calls `fun.(ref_elements2, set2)` for a range of
  size and overlap combinations.

  Options:
  - `:test_variants2` — also test sequential "all before"/"all after" sets
  - `:max_combos` — limit the number of param combinations tried (default: all)
  """
  def foreach_second_set(fun, size, ref_elements, opts \\ []) do
    foreach_second_set_variants1(fun, size, ref_elements, opts)

    if Keyword.get(opts, :test_variants2, false) do
      foreach_second_set_variants2(fun, size, ref_elements)
    end

    :ok
  end

  defp foreach_second_set_variants1(fun, size, ref_elements, opts) do
    amounts2 =
      :lists.usort([
        0,
        1,
        size,
        :rand.uniform(max(1, size)),
        :rand.uniform(size + 100)
      ])

    percentages_in_common = [0.0, 0.5, 1.0]

    param_combos =
      for amount2 <- amounts2, pct <- percentages_in_common, do: {amount2, pct}

    max_combos = Keyword.get(opts, :max_combos, length(param_combos))

    param_combos
    |> Xb5TestUtils.list_shuffle()
    |> Enum.take(max_combos)
    |> Enum.each(fn {amount2, pct_in_common} ->
      repeated_amount = floor(pct_in_common * min(amount2, size))
      new_amount = amount2 - repeated_amount

      repeated_elements =
        ref_elements
        |> Xb5TestUtils.list_shuffle()
        |> Enum.take(repeated_amount)

      new_elements = for _ <- 1..new_amount//1, do: Xb5TestUtils.new_element()

      ref_elements2 =
        (repeated_elements ++ new_elements)
        |> :lists.usort()
        |> Enum.map(&Xb5TestUtils.randomly_switch_number_type/1)

      set2 = Xb5.Set.new(maybe_shuffle_for_new_set(ref_elements2))

      fun.(ref_elements2, set2)
    end)
  end

  defp foreach_second_set_variants2(fun, size, ref_elements) do
    amounts2 = Enum.filter(:lists.usort([0, 1, size - 1, size + 1]), &(&1 >= 0))

    for placement <- [:before, :after_], amount2 <- amounts2 do
      ref_elements2 = sequential_ref_elements(placement, amount2, ref_elements)
      set2 = Xb5.Set.new(ref_elements2)
      fun.(ref_elements2, set2)
    end
  end

  defp sequential_ref_elements(_placement, 0, _ref_elements), do: []
  defp sequential_ref_elements(_placement, _size, []), do: []

  defp sequential_ref_elements(:before, size, ref_elements) do
    sequential_ref_elements_before(size, hd(ref_elements), [])
  end

  defp sequential_ref_elements(:after_, size, ref_elements) do
    sequential_ref_elements_after(size, List.last(ref_elements))
  end

  defp sequential_ref_elements_before(0, _next, acc), do: acc

  defp sequential_ref_elements_before(size, next, acc) do
    smaller = Xb5TestUtils.element_smaller(next)
    assert smaller < next
    sequential_ref_elements_before(size - 1, smaller, [smaller | acc])
  end

  defp sequential_ref_elements_after(0, _prev), do: []

  defp sequential_ref_elements_after(size, prev) do
    larger = Xb5TestUtils.element_larger(prev)
    assert larger > prev
    [larger | sequential_ref_elements_after(size - 1, larger)]
  end
end
