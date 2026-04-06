defmodule Xb5BagTestUtils do
  @moduledoc """
  Test helpers specific to `Xb5.Bag`. Translated from the per-suite helpers in
  `xb5_bag_test_SUITE.erl` that are bag-specific (repeated element generation,
  etc).
  """

  import ExUnit.Assertions

  # new_ref_elements/1: generates `size` elements with ~20% repetition chance.
  # Each step: if acc is non-empty and rand < 0.20, pick a random existing element
  # (applying randomly_switch_number_type), else generate a new unique element.
  # Result is :lists.sort(acc) (NOT usort — duplicates are kept).

  def new_ref_elements(size), do: new_ref_elements_recur(size, [])

  defp new_ref_elements_recur(0, acc), do: :lists.sort(acc)

  defp new_ref_elements_recur(remaining, acc) do
    if acc != [] and :rand.uniform() < 0.20 do
      repeated = acc |> Enum.random() |> Xb5TestUtils.randomly_switch_number_type()
      new_ref_elements_recur(remaining - 1, [repeated | acc])
    else
      elem = Xb5TestUtils.new_element()

      if Enum.any?(acc, &(&1 == elem)) do
        new_ref_elements_recur(remaining, acc)
      else
        new_ref_elements_recur(remaining - 1, [elem | acc])
      end
    end
  end

  # new_bag_from_each_pushed/1: builds a bag by calling Xb5.Bag.push/2 for each element.
  # Asserts the initial bag has size 0.
  def new_bag_from_each_pushed(list) do
    bag = Xb5.Bag.new()
    assert Xb5.Bag.size(bag) == 0
    Enum.reduce(list, bag, fn elem, acc -> Xb5.Bag.push(acc, elem) end)
  end

  # maybe_shuffle_for_new_bag/1: returns list unchanged 2/3 of the time, shuffled 1/3.
  def maybe_shuffle_for_new_bag(list) do
    if :rand.uniform() < 1 / 3, do: Xb5TestUtils.list_shuffle(list), else: list
  end

  # foreach_tested_size/1: calls fun.(size, ref_elements) for 200 diverse sizes.
  def foreach_tested_size(fun) do
    Xb5TestUtils.foreach_tested_size(fn size ->
      ref_elements = new_ref_elements(size)
      fun.(size, ref_elements)
    end)
  end

  # foreach_test_bag/1: calls fun.(size, ref_elements, bag) for 200 diverse sizes.
  def foreach_test_bag(fun) do
    foreach_tested_size(fn size, ref_elements ->
      bag = new_bag_from_each_pushed(maybe_shuffle_for_new_bag(ref_elements))
      assert Xb5.Bag.size(bag) == size
      fun.(size, ref_elements, bag)
    end)
  end

  # foreach_second_bag/4: generates partner bags and calls fun.(ref_elements2, bag2).
  def foreach_second_bag(fun, size, ref_elements, opts \\ []) do
    amounts2 =
      :lists.usort([
        0,
        1,
        size,
        :rand.uniform(max(1, size)),
        :rand.uniform(size + 100)
      ])

    percentages_in_common = [0.0, 0.5, 1.0]
    param_combos = for a <- amounts2, p <- percentages_in_common, do: {a, p}
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
        |> :lists.sort()
        |> Enum.map(&Xb5TestUtils.randomly_switch_number_type/1)

      bag2 = Xb5.Bag.new(maybe_shuffle_for_new_bag(ref_elements2))
      fun.(ref_elements2, bag2)
    end)
  end
end
