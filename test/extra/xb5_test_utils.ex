defmodule Xb5TestUtils do
  import Bitwise

  @moduledoc """
  Shared test utilities, translated from `xb5_test_utils.erl` and the
  common helpers in the xb5 CT suites. Contains only type-agnostic code.
  """

  # 1 bsl 128 — a large integer that sorts below every non-number BEAM type.
  @large_integer 340_282_366_920_938_463_463_374_607_431_768_211_456

  # -------------------------------------------------------------------------
  # Size iteration
  # -------------------------------------------------------------------------

  @mandatory_sizes Enum.to_list(0..30) ++ Enum.to_list(40..200//20)
  @total_iterations 200

  @doc """
  Calls `fun.(size)` for #{@total_iterations} sizes: every integer 0–30,
  then 40–200 in steps of 20, plus enough random sizes to reach the total.

  Random sizes are weighted: ⅔ in 0–200, ²⁄₉ in 201–500, ¹⁄₉ in 501–1000.
  """
  def foreach_tested_size(fun) do
    random_count = @total_iterations - length(@mandatory_sizes)
    random_sizes = for _ <- 1..random_count//1, do: new_random_size()

    (random_sizes ++ @mandatory_sizes)
    |> Enum.each(fn size -> fun.(size) end)
  end

  defp new_random_size do
    die = :rand.uniform()

    cond do
      die < 2 / 3 -> :rand.uniform(201) - 1
      die < 2 / 3 + 2 / 9 -> 200 + :rand.uniform(300)
      true -> 500 + :rand.uniform(500)
    end
  end

  # -------------------------------------------------------------------------
  # Element generation
  # -------------------------------------------------------------------------

  @doc """
  Generates a random element. Distribution (matching the Erlang suite):
  25/30 number, 1/30 each of binary, tuple, list, map, and reference.
  """
  def new_element do
    case :rand.uniform(30) do
      d when d <= 25 ->
        new_number()

      26 ->
        :crypto.strong_rand_bytes(:rand.uniform(16))

      27 ->
        n = :rand.uniform(10) - 1
        List.to_tuple(for _ <- 1..n//1, do: new_number())

      28 ->
        n = :rand.uniform(10) - 1
        for _ <- 1..n//1, do: new_number()

      29 ->
        n = :rand.uniform(10) - 1
        Map.new(for _ <- 1..n//1, do: {new_number(), new_number()})

      30 ->
        make_ref()
    end
  end

  @doc "Generates a random integer or float in -(2^49)..(2^49-1)."
  def new_number do
    (:rand.uniform(1 <<< 50) - (1 <<< 49))
    |> randomly_switch_number_type()
  end

  @doc """
  With probability 1/3, converts an integer to its float equivalent or vice
  versa. Exercises the `==`-but-not-`===` equality path in the B-tree.
  """
  def randomly_switch_number_type(elem) do
    case :rand.uniform(3) do
      1 when is_integer(elem) -> elem * 1.0
      1 when is_float(elem) -> trunc(elem)
      _ -> elem
    end
  end

  @doc """
  Normalises a value for comparison: whole-number floats become integers,
  composite types are normalised recursively.
  """
  def canon_element(elem) when is_float(elem) do
    if :math.fmod(elem, 1.0) == 0.0, do: trunc(elem), else: elem
  end

  def canon_element(elem) when is_list(elem), do: Enum.map(elem, &canon_element/1)

  def canon_element(elem) when is_tuple(elem) do
    elem |> Tuple.to_list() |> Enum.map(&canon_element/1) |> List.to_tuple()
  end

  def canon_element(elem) when is_map(elem) do
    Map.new(elem, fn {k, v} -> {canon_element(k), canon_element(v)} end)
  end

  def canon_element(elem), do: elem

  # -------------------------------------------------------------------------
  # Element ordering helpers
  # -------------------------------------------------------------------------

  @doc "Returns an element guaranteed to be strictly less than `elem`."
  def element_smaller(elem) when is_number(elem), do: trunc(elem) - 1
  # References sort before tuples in BEAM term order.
  def element_smaller(elem) when is_tuple(elem), do: make_ref()
  # @large_integer is a number, which sorts before all non-number types.
  def element_smaller(_elem), do: @large_integer

  @doc "Returns an element guaranteed to be strictly greater than `elem`."
  def element_larger(elem) when is_binary(elem), do: elem <> <<95>>
  # Binaries sort last in BEAM term order, so any binary > any non-binary.
  def element_larger(_elem), do: "ensured to be larger"

  @doc """
  Returns `{:found, value}` strictly between `elem1` and `elem2`, or `:none`.
  Only handles numeric cases and the numeric-to-other-type boundary.
  """
  def element_in_between(elem1, elem2) do
    cond do
      is_number(elem1) and is_number(elem2) and elem2 - elem1 > 1 ->
        {:found, trunc(elem1) + 1}

      is_number(elem1) and not is_number(elem2) ->
        {:found, trunc(elem1) + 1}

      true ->
        :none
    end
  end

  # -------------------------------------------------------------------------
  # Sorted-list helpers
  # -------------------------------------------------------------------------

  @doc "Inserts `elem` into `sorted_list`, preserving order (using `>`)."
  def add_to_sorted_list(elem, [h | t]) do
    if elem > h, do: [h | add_to_sorted_list(elem, t)], else: [elem, h | t]
  end

  def add_to_sorted_list(elem, []), do: [elem]

  @doc "Removes the first occurrence of `elem` (by `==`) from `sorted_list`."
  def remove_from_sorted_list(elem, [h | t]) do
    cond do
      elem > h -> [h | remove_from_sorted_list(elem, t)]
      elem == h -> t
    end
  end

  # -------------------------------------------------------------------------
  # Sampling helpers
  # -------------------------------------------------------------------------

  @doc "Shuffles `list` by assigning random weights then sorting."
  def list_shuffle(list) do
    list
    |> Enum.map(fn elem -> {:rand.uniform(), elem} end)
    |> Enum.sort_by(fn {w, _} -> w end)
    |> Enum.map(fn {_, elem} -> elem end)
  end

  @doc """
  Picks up to `amount` elements from `ref_elements` (shuffled), applies
  `randomly_switch_number_type/1` to each, and calls `fun.(elem)` on each.
  """
  def foreach_existing_element(fun, ref_elements, amount) do
    ref_elements
    |> list_shuffle()
    |> Enum.take(amount)
    |> Enum.each(fn elem -> fun.(randomly_switch_number_type(elem)) end)
  end

  @doc """
  Generates `amount` elements absent from `ref_elements` (checked with `==`)
  and calls `fun.(elem)` on each.
  """
  def foreach_non_existent_element(_fun, _ref_elements, 0), do: :ok

  def foreach_non_existent_element(fun, ref_elements, amount) do
    elem = new_element()

    if Enum.any?(ref_elements, &(&1 == elem)) do
      foreach_non_existent_element(fun, ref_elements, amount)
    else
      fun.(elem)
      foreach_non_existent_element(fun, ref_elements, amount - 1)
    end
  end
end
