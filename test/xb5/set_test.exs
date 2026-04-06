defmodule Xb5SetTest do
  use ExUnit.Case, async: true
  @moduletag :set

  alias Xb5TestUtils, as: TU
  alias Xb5SetTestUtils, as: STU

  doctest Xb5.Set

  # ---------------------------------------------------------------------------
  # Basic API
  # ---------------------------------------------------------------------------

  describe "construction" do
    test "from enumerable matches element-wise insertion and size" do
      STU.foreach_tested_size(fn size, ref_elements ->
        set = Xb5.Set.new(ref_elements)
        assert Xb5.Set.to_list(set) == ref_elements
        assert Xb5.Set.size(set) == size

        assert Xb5.Set.to_list(STU.new_set_from_each_inserted(ref_elements)) == ref_elements
      end)
    end
  end

  describe "construction_repeated" do
    test "inserting existing elements does not change size or contents" do
      STU.foreach_tested_size(fn size, ref_elements ->
        amount = min(length(ref_elements), 50)
        elements_to_repeat = ref_elements |> TU.list_shuffle() |> Enum.take(amount)

        Enum.each(elements_to_repeat, fn elem_to_repeat ->
          list =
            TU.add_to_sorted_list(TU.randomly_switch_number_type(elem_to_repeat), ref_elements)

          set = Xb5.Set.new(list)
          assert Xb5.Set.size(set) == size
          assert Xb5.Set.to_list(set) == ref_elements

          set_shuffled = Xb5.Set.new(TU.list_shuffle(list))
          assert Xb5.Set.size(set_shuffled) == size
          assert Xb5.Set.to_list(set_shuffled) == ref_elements
        end)
      end)
    end
  end

  describe "member?" do
    test "existing elements are found, absent elements are not" do
      STU.foreach_test_set(fn size, ref_elements, set ->
        TU.foreach_existing_element(
          fn elem -> assert Xb5.Set.member?(set, elem) end,
          ref_elements,
          size
        )

        TU.foreach_non_existent_element(
          fn elem -> refute Xb5.Set.member?(set, elem) end,
          ref_elements,
          100
        )
      end)
    end
  end

  describe "put" do
    test "putting an existing element is a no-op; putting a new one grows the set" do
      STU.foreach_test_set(fn size, ref_elements, set ->
        TU.foreach_existing_element(
          fn elem ->
            set2 = Xb5.Set.put(set, elem)
            assert Xb5.Set.size(set2) == size
            assert Xb5.Set.to_list(set2) == ref_elements
          end,
          ref_elements,
          min(50, size)
        )

        TU.foreach_non_existent_element(
          fn elem ->
            set2 = Xb5.Set.put(set, elem)
            assert Xb5.Set.size(set2) == size + 1
            assert Xb5.Set.to_list(set2) == TU.add_to_sorted_list(elem, ref_elements)
          end,
          ref_elements,
          50
        )
      end)
    end
  end

  describe "delete_sequential" do
    test "deletes elements one by one in order, interleaved with absent-key checks" do
      STU.foreach_test_set(fn _size, ref_elements, set ->
        delete_keys = Enum.map(ref_elements, &TU.randomly_switch_number_type/1)

        {set_n, []} =
          Enum.reduce(delete_keys, {set, ref_elements}, fn elem, {set1, remaining1} ->
            check_delete_absent(set1, remaining1, 3)

            set2 = Xb5.Set.delete(set1, elem)
            remaining2 = TU.remove_from_sorted_list(elem, remaining1)
            assert Xb5.Set.to_list(set2) == remaining2
            assert Xb5.Set.size(set2) == length(remaining2)

            {set2, remaining2}
          end)

        assert Xb5.Set.to_list(set_n) == []
        assert Xb5.Set.size(set_n) == 0

        check_delete_absent(set_n, [], 3)
      end)
    end
  end

  describe "delete_shuffled" do
    test "deletes elements in random order, interleaved with absent-key checks" do
      STU.foreach_test_set(fn _size, ref_elements, set ->
        delete_keys =
          ref_elements
          |> TU.list_shuffle()
          |> Enum.map(&TU.randomly_switch_number_type/1)

        {set_n, []} =
          Enum.reduce(delete_keys, {set, ref_elements}, fn elem, {set1, remaining1} ->
            check_delete_absent(set1, remaining1, 3)

            set2 = Xb5.Set.delete(set1, elem)
            remaining2 = TU.remove_from_sorted_list(elem, remaining1)
            assert Xb5.Set.to_list(set2) == remaining2
            assert Xb5.Set.size(set2) == length(remaining2)

            {set2, remaining2}
          end)

        assert Xb5.Set.to_list(set_n) == []
        assert Xb5.Set.size(set_n) == 0

        check_delete_absent(set_n, [], 3)
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # first/last/lower/higher
  # ---------------------------------------------------------------------------

  describe "first" do
    test "returns nil default on empty set, returns first element otherwise" do
      STU.foreach_test_set(fn
        0, _ref_elements, set ->
          assert Xb5.Set.first(set) == nil
          assert Xb5.Set.first(set, :empty) == :empty

        _size, ref_elements, set ->
          assert Xb5.Set.first(set) == hd(ref_elements)
          assert Xb5.Set.first(set, :empty) == hd(ref_elements)
      end)
    end
  end

  describe "first!" do
    test "raises on empty set, returns first element otherwise" do
      STU.foreach_test_set(fn
        0, _ref_elements, set ->
          assert_raise Xb5.EmptyError, fn -> Xb5.Set.first!(set) end

        _size, ref_elements, set ->
          assert Xb5.Set.first!(set) == hd(ref_elements)
      end)
    end
  end

  describe "last" do
    test "returns nil default on empty set, returns last element otherwise" do
      STU.foreach_test_set(fn
        0, _ref_elements, set ->
          assert Xb5.Set.last(set) == nil
          assert Xb5.Set.last(set, :empty) == :empty

        _size, ref_elements, set ->
          assert Xb5.Set.last(set) == List.last(ref_elements)
          assert Xb5.Set.last(set, :empty) == List.last(ref_elements)
      end)
    end
  end

  describe "last!" do
    test "raises on empty set, returns last element otherwise" do
      STU.foreach_test_set(fn
        0, _ref_elements, set ->
          assert_raise Xb5.EmptyError, fn -> Xb5.Set.last!(set) end

        _size, ref_elements, set ->
          assert Xb5.Set.last!(set) == List.last(ref_elements)
      end)
    end
  end

  describe "lower" do
    test "returns the nearest element strictly below the query, or :error" do
      STU.foreach_test_set(fn _size, ref_elements, set ->
        run_lower(ref_elements, set)
      end)
    end
  end

  describe "higher" do
    test "returns the nearest element strictly above the query, or :error" do
      STU.foreach_test_set(fn _size, ref_elements, set ->
        run_higher(ref_elements, set)
      end)
    end
  end

  describe "pop_first!" do
    test "raises on empty set, repeatedly pops first element in order" do
      STU.foreach_test_set(fn _size, ref_elements, set ->
        run_pop_first(ref_elements, set)
      end)
    end
  end

  describe "pop_last!" do
    test "raises on empty set, repeatedly pops last element in order" do
      STU.foreach_test_set(fn _size, ref_elements, set ->
        run_pop_last(Enum.reverse(ref_elements), set)
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Set Operations
  # ---------------------------------------------------------------------------

  describe "difference" do
    test "self-difference is empty; general difference matches ordsets:subtract" do
      STU.foreach_test_set(fn size, ref_elements, set ->
        self_diff = Xb5.Set.difference(set, set)
        assert Xb5.Set.size(self_diff) == 0
        assert Xb5.Set.to_list(self_diff) == []

        STU.foreach_second_set(
          fn ref_elements2, set2 ->
            difference = Xb5.Set.difference(set, set2)

            expected =
              :ordsets.subtract(
                :ordsets.from_list(ref_elements),
                :ordsets.from_list(ref_elements2)
              )

            assert Xb5.Set.size(difference) == :ordsets.size(expected)
            assert Xb5.Set.to_list(difference) == :ordsets.to_list(expected)
          end,
          size,
          ref_elements
        )
      end)
    end
  end

  describe "intersection" do
    test "self-intersection is identity; general intersection matches ordsets:intersection" do
      STU.foreach_test_set(fn size, ref_elements, set ->
        self_intersect = Xb5.Set.intersection(set, set)
        assert Xb5.Set.size(self_intersect) == size
        assert Xb5.Set.to_list(self_intersect) == ref_elements

        STU.foreach_second_set(
          fn ref_elements2, set2 ->
            intersection = Xb5.Set.intersection(set, set2)

            expected =
              :ordsets.intersection(
                :ordsets.from_list(ref_elements),
                :ordsets.from_list(ref_elements2)
              )

            assert Xb5.Set.size(intersection) == :ordsets.size(expected)
            assert Xb5.Set.to_list(intersection) == :ordsets.to_list(expected)
          end,
          size,
          ref_elements
        )
      end)
    end
  end

  describe "disjoint?" do
    test "set is disjoint with itself iff empty; general case matches ordsets:is_disjoint" do
      STU.foreach_test_set(fn size, ref_elements, set ->
        assert Xb5.Set.disjoint?(set, set) == (size == 0)

        STU.foreach_second_set(
          fn ref_elements2, set2 ->
            is_disjoint = Xb5.Set.disjoint?(set, set2)

            expected =
              :ordsets.is_disjoint(
                :ordsets.from_list(ref_elements),
                :ordsets.from_list(ref_elements2)
              )

            assert is_disjoint == expected
            assert Xb5.Set.disjoint?(set2, set) == expected
          end,
          size,
          ref_elements
        )
      end)
    end
  end

  describe "equal?" do
    test "set equals itself; general case matches list equality" do
      STU.foreach_test_set(fn size, ref_elements, set ->
        assert Xb5.Set.equal?(set, set)

        STU.foreach_second_set(
          fn ref_elements2, set2 ->
            is_equal = Xb5.Set.equal?(set, set2)
            assert is_equal == (ref_elements == ref_elements2)
            assert Xb5.Set.equal?(set2, set) == is_equal
          end,
          size,
          ref_elements
        )
      end)
    end
  end

  describe "subset?" do
    test "set is a subset of itself; general case matches ordsets:is_subset" do
      STU.foreach_test_set(fn size, ref_elements, set ->
        assert Xb5.Set.subset?(set, set)

        STU.foreach_second_set(
          fn ref_elements2, set2 ->
            is_subset = Xb5.Set.subset?(set, set2)

            expected =
              :ordsets.is_subset(
                :ordsets.from_list(ref_elements),
                :ordsets.from_list(ref_elements2)
              )

            assert is_subset == expected

            if Xb5.Set.size(set) == Xb5.Set.size(set2) do
              assert Xb5.Set.subset?(set2, set) == is_subset
            end
          end,
          size,
          ref_elements
        )
      end)
    end
  end

  describe "union" do
    test "self-union is identity; general union matches :lists.usort of concatenation" do
      STU.foreach_test_set(fn size, ref_elements, set ->
        self_union = Xb5.Set.union(set, set)
        assert Xb5.Set.size(self_union) == size
        assert Xb5.Set.to_list(self_union) == ref_elements

        STU.foreach_second_set(
          fn ref_elements2, set2 ->
            expected = :lists.usort(ref_elements ++ ref_elements2)

            union = Xb5.Set.union(set, set2)
            assert Xb5.Set.size(union) == length(expected)
            assert Xb5.Set.to_list(union) == expected

            union2 = Xb5.Set.union(set2, set)
            assert Xb5.Set.size(union2) == length(expected)
            assert Xb5.Set.to_list(union2) == expected
          end,
          size,
          ref_elements,
          test_variants2: true
        )
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Additional Functions
  # ---------------------------------------------------------------------------

  describe "filter" do
    test "filtered set contains exactly the elements for which fun returns truthy" do
      STU.foreach_test_set(fn size, ref_elements, set ->
        amounts_to_remove =
          case size do
            0 -> [0]
            _ -> :lists.usort([0, 1, size, size - 1, :rand.uniform(size), :rand.uniform(size)])
          end

        Enum.each(amounts_to_remove, fn amount_to_remove ->
          if size == 0 do
            filtered = Xb5.Set.filter(set, fn _ -> raise "should not be called" end)
            assert Xb5.Set.to_list(filtered) == []
            assert Xb5.Set.size(filtered) == 0
          else
            elements_to_remove =
              ref_elements |> TU.list_shuffle() |> Enum.take(amount_to_remove)

            aux_set = :gb_sets.from_list(elements_to_remove)
            filter_fun = fn e -> not :gb_sets.is_element(e, aux_set) end

            filtered = Xb5.Set.filter(set, filter_fun)

            expected = Enum.filter(ref_elements, filter_fun)
            assert Xb5.Set.to_list(filtered) == expected
            assert Xb5.Set.size(filtered) == length(expected)
          end
        end)
      end)
    end
  end

  describe "map" do
    test "mapped set contains unique transformed elements, deduplicated and sorted" do
      STU.foreach_test_set(fn _size, ref_elements, set ->
        Enum.each([0.0, 0.2, 0.5, 0.7, 1.0], fn pct_mapped ->
          phash_range = 100_000
          phash_ceiling = round(pct_mapped * phash_range)
          random_factor = :rand.uniform()

          map_fun = fn e ->
            canon_e = TU.canon_element(e)

            if :erlang.phash2(canon_e, phash_range) < phash_ceiling do
              :erlang.phash2([random_factor | canon_e], 3)
            else
              e
            end
          end

          mapped_set = Xb5.Set.map(set, map_fun)
          expected = ref_elements |> Enum.map(map_fun) |> :lists.usort()

          assert Xb5.Set.size(mapped_set) == length(expected)
          assert Xb5.Set.to_list(mapped_set) == expected
        end)
      end)
    end
  end

  describe "new/1 with native Erlang xb5_sets term" do
    test "round-trips through :xb5_sets.wrap/unwrap!" do
      assert {:error, _} = :xb5_sets.unwrap(:xb5_bag.new())
      assert {:error, _} = :xb5_sets.unwrap(:xb5_trees.new())
      assert {:error, _} = :xb5_sets.unwrap({:xb5_set, -1, :xb5_sets_node.new()})
      assert {:error, _} = :xb5_sets.unwrap({:xb5_set, 2, :xb5_sets_node.new()})
      assert {:error, _} = :xb5_sets.unwrap({:xb5_set, 2, make_ref()})

      STU.foreach_test_set(fn _size, _ref_elements, set ->
        erlang_set = :xb5_sets.wrap(%{size: set.size, root: set.root})

        set2 = Xb5.Set.new(erlang_set)

        assert set2 == set
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Generates `amount` non-member elements and asserts delete is idempotent.
  # (Erlang's xb5_sets:delete raises on missing key; Xb5.Set.delete is idempotent.)
  defp check_delete_absent(_set, _remaining, 0), do: :ok

  defp check_delete_absent(set, remaining, amount) do
    elem = TU.new_element()

    if Enum.any?(remaining, &(&1 == elem)) do
      check_delete_absent(set, remaining, amount)
    else
      assert Xb5.Set.delete(set, elem) == set
      check_delete_absent(set, remaining, amount - 1)
    end
  end

  # -----

  defp run_lower([], set) do
    elem = TU.new_element()
    assert Xb5.Set.lower(set, elem) == :error
  end

  defp run_lower([single], set) do
    assert Xb5.Set.lower(set, TU.randomly_switch_number_type(single)) == :error

    larger = TU.element_larger(single)
    assert Xb5.Set.lower(set, larger) == {:ok, single}

    smaller = TU.element_smaller(single)
    assert Xb5.Set.lower(set, smaller) == :error
  end

  defp run_lower([first | next], set) do
    assert Xb5.Set.lower(set, TU.randomly_switch_number_type(first)) == :error

    smaller = TU.element_smaller(first)
    assert Xb5.Set.lower(set, smaller) == :error

    run_lower_recur(first, next, set)
  end

  defp run_lower_recur(expected, [last], set) do
    result = Xb5.Set.lower(set, TU.randomly_switch_number_type(last))
    assert result == {:ok, expected}

    larger = TU.element_larger(last)
    assert larger > last
    assert Xb5.Set.lower(set, larger) == {:ok, last}
  end

  defp run_lower_recur(expected, [elem | next], set) do
    assert Xb5.Set.lower(set, TU.randomly_switch_number_type(elem)) == {:ok, expected}

    case TU.element_in_between(expected, elem) do
      {:found, in_between} ->
        assert in_between > expected
        assert in_between < elem
        assert Xb5.Set.lower(set, in_between) == {:ok, expected}

      :none ->
        :ok
    end

    run_lower_recur(elem, next, set)
  end

  # -----

  defp run_higher(ref_elements, set) do
    case Enum.reverse(ref_elements) do
      [] ->
        elem = TU.new_element()
        assert Xb5.Set.higher(set, elem) == :error

      [single] ->
        assert Xb5.Set.higher(set, single) == :error

        larger = TU.element_larger(single)
        assert Xb5.Set.higher(set, larger) == :error

        smaller = TU.element_smaller(single)
        assert Xb5.Set.higher(set, smaller) == {:ok, single}

      [last | next] ->
        assert Xb5.Set.higher(set, TU.randomly_switch_number_type(last)) == :error

        larger = TU.element_larger(last)
        assert Xb5.Set.higher(set, larger) == :error

        run_higher_recur(last, next, set)
    end
  end

  defp run_higher_recur(expected, [first], set) do
    result = Xb5.Set.higher(set, TU.randomly_switch_number_type(first))
    assert result == {:ok, expected}

    smaller = TU.element_smaller(first)
    assert smaller < first
    assert Xb5.Set.higher(set, smaller) == {:ok, first}
  end

  defp run_higher_recur(expected, [elem | next], set) do
    assert Xb5.Set.higher(set, TU.randomly_switch_number_type(elem)) == {:ok, expected}

    case TU.element_in_between(elem, expected) do
      {:found, in_between} ->
        assert in_between < expected
        assert in_between > elem
        assert Xb5.Set.higher(set, in_between) == {:ok, expected}

      :none ->
        :ok
    end

    run_higher_recur(elem, next, set)
  end

  # -----

  defp run_pop_first([expected | next], set) do
    {taken, set2} = Xb5.Set.pop_first!(set)
    assert taken == expected
    assert Xb5.Set.size(set2) == length(next)
    run_pop_first(next, set2)
  end

  defp run_pop_first([], set) do
    assert_raise Xb5.EmptyError, fn -> Xb5.Set.pop_first!(set) end
  end

  defp run_pop_last([expected | next], set) do
    {taken, set2} = Xb5.Set.pop_last!(set)
    assert taken == expected
    assert Xb5.Set.size(set2) == length(next)
    run_pop_last(next, set2)
  end

  defp run_pop_last([], set) do
    assert_raise Xb5.EmptyError, fn -> Xb5.Set.pop_last!(set) end
  end

  # ---------------------------------------------------------------------------
  # Protocol coverage
  # ---------------------------------------------------------------------------

  describe "additional Set API" do
    test "reject keeps elements for which fun is falsy" do
      STU.foreach_test_set(fn _size, ref_elements, set ->
        pred = fn x -> rem(:erlang.phash2(TU.canon_element(x)), 2) == 0 end
        set2 = Xb5.Set.reject(set, pred)
        expected = Enum.reject(ref_elements, pred)
        assert Xb5.Set.size(set2) == length(expected)
        assert canon_elems(Xb5.Set.to_list(set2)) == canon_elems(expected)
      end)
    end

    test "symmetric_difference gives elements in exactly one set, both orderings verified" do
      STU.foreach_test_set(fn size, ref_elements, set ->
        STU.foreach_second_set(
          fn ref_elements2, set2 ->
            result_ab = Xb5.Set.symmetric_difference(set, set2)
            result_ba = Xb5.Set.symmetric_difference(set2, set)

            elems1 = MapSet.new(ref_elements, &TU.canon_element/1)
            elems2 = MapSet.new(ref_elements2, &TU.canon_element/1)
            expected = MapSet.symmetric_difference(elems1, elems2)

            assert Xb5.Set.size(result_ab) == MapSet.size(expected)
            assert Xb5.Set.size(result_ba) == MapSet.size(expected)

            Enum.each(canon_elems(Xb5.Set.to_list(result_ab)), fn e ->
              assert MapSet.member?(expected, e)
            end)

            Enum.each(canon_elems(Xb5.Set.to_list(result_ba)), fn e ->
              assert MapSet.member?(expected, e)
            end)
          end,
          size,
          ref_elements
        )
      end)
    end

    test "split_with partitions by predicate" do
      STU.foreach_test_set(fn _size, ref_elements, set ->
        pred = fn x -> rem(:erlang.phash2(TU.canon_element(x)), 2) == 0 end
        {t_true, t_false} = Xb5.Set.split_with(set, pred)
        expected_true = Enum.filter(ref_elements, pred)
        expected_false = Enum.reject(ref_elements, pred)
        assert Xb5.Set.size(t_true) == length(expected_true)
        assert canon_elems(Xb5.Set.to_list(t_true)) == canon_elems(expected_true)
        assert Xb5.Set.size(t_false) == length(expected_false)
        assert canon_elems(Xb5.Set.to_list(t_false)) == canon_elems(expected_false)
      end)
    end

    test "new/2 with transform" do
      STU.foreach_test_set(fn _size, ref_elements, _set ->
        transform = fn x -> {x, :transformed} end
        set2 = Xb5.Set.new(ref_elements, transform)
        expected = ref_elements |> Enum.map(transform) |> :lists.usort()
        assert Xb5.Set.size(set2) == length(expected)
        assert canon_elems(Xb5.Set.to_list(set2)) == canon_elems(expected)
      end)
    end

    test "new/2 with Erlang term and transform" do
      base = Xb5.Set.new([1, 2, 3])
      erlang_set = :xb5_sets.wrap(Xb5.Set.unwrap!(base))
      set = Xb5.Set.new(erlang_set, fn x -> x * 2 end)
      assert Xb5.Set.to_list(set) == [2, 4, 6]
    end
  end

  # ---------------------------------------------------------------------------
  # Stream API
  # ---------------------------------------------------------------------------

  describe "stream" do
    test "asc matches to_list" do
      STU.foreach_test_set(fn size, ref_elements, set ->
        result = Xb5.Set.stream(set) |> Enum.to_list()
        assert canon_elems(result) == canon_elems(ref_elements)
        assert length(result) == size
      end)
    end

    test "desc matches desc to_list" do
      STU.foreach_test_set(fn size, ref_elements, set ->
        result = Xb5.Set.stream(set, :desc) |> Enum.to_list()
        assert canon_elems(result) == canon_elems(Enum.reverse(ref_elements))
        assert length(result) == size
      end)
    end

    test "partial consumption via Enum.take" do
      STU.foreach_test_set(fn size, ref_elements, set ->
        if size >= 2 do
          take = div(size, 2)
          result = Xb5.Set.stream(set) |> Enum.take(take)
          assert canon_elems(result) == canon_elems(Enum.take(ref_elements, take))
        end
      end)
    end
  end

  describe "stream_from" do
    test "asc: multiple sampled existing elements as start points" do
      STU.foreach_test_set(fn size, ref_elements, set ->
        if size > 0 do
          ref_elements
          |> TU.list_shuffle()
          |> Enum.take(10)
          |> Enum.each(fn start_elem ->
            result = Xb5.Set.stream_from(set, start_elem) |> Enum.to_list()
            expected = Enum.drop_while(ref_elements, fn e -> e < start_elem end)
            assert canon_elems(result) == canon_elems(expected)
          end)
        end
      end)
    end

    test "asc: starting below all elements yields full stream" do
      STU.foreach_test_set(fn size, ref_elements, set ->
        if size > 0 do
          before_all = TU.element_smaller(hd(ref_elements))
          result = Xb5.Set.stream_from(set, before_all) |> Enum.to_list()
          assert canon_elems(result) == canon_elems(ref_elements)
        end
      end)
    end

    test "asc: starting above all elements yields empty stream" do
      STU.foreach_test_set(fn size, ref_elements, set ->
        if size > 0 do
          after_all = TU.element_larger(List.last(ref_elements))
          assert Xb5.Set.stream_from(set, after_all) |> Enum.to_list() == []
        end
      end)
    end

    test "desc: multiple sampled existing elements as start points" do
      STU.foreach_test_set(fn size, ref_elements, set ->
        if size > 0 do
          ref_elements
          |> TU.list_shuffle()
          |> Enum.take(10)
          |> Enum.each(fn start_elem ->
            result = Xb5.Set.stream_from(set, start_elem, :desc) |> Enum.to_list()

            expected =
              ref_elements |> Enum.take_while(fn e -> e <= start_elem end) |> Enum.reverse()

            assert canon_elems(result) == canon_elems(expected)
          end)
        end
      end)
    end

    test "desc: starting above all elements yields full desc stream" do
      STU.foreach_test_set(fn size, ref_elements, set ->
        if size > 0 do
          after_all = TU.element_larger(List.last(ref_elements))
          result = Xb5.Set.stream_from(set, after_all, :desc) |> Enum.to_list()
          assert canon_elems(result) == canon_elems(Enum.reverse(ref_elements))
        end
      end)
    end

    test "desc: starting below all elements yields empty stream" do
      STU.foreach_test_set(fn size, ref_elements, set ->
        if size > 0 do
          before_all = TU.element_smaller(hd(ref_elements))
          assert Xb5.Set.stream_from(set, before_all, :desc) |> Enum.to_list() == []
        end
      end)
    end
  end

  describe "Enumerable protocol" do
    test "count, member?, reduce, and slice" do
      STU.foreach_test_set(fn size, ref_elements, set ->
        assert Enum.count(set) == size

        TU.foreach_existing_element(
          fn elem ->
            assert Enum.member?(set, elem)
          end,
          ref_elements,
          min(5, size)
        )

        TU.foreach_non_existent_element(
          fn elem ->
            refute Enum.member?(set, elem)
          end,
          ref_elements,
          3
        )

        assert canon_elems(Enum.to_list(set)) == canon_elems(ref_elements)

        if size >= 2 do
          slice_start = div(size, 4)
          slice_len = max(1, div(size, 2))
          sliced = Enum.slice(set, slice_start, slice_len)
          expected_slice = Enum.slice(ref_elements, slice_start, slice_len)
          assert canon_elems(sliced) == canon_elems(expected_slice)
        end
      end)
    end

    test "Enum.slice with step and non-zero start" do
      set = Xb5.Set.new([1, 2, 3, 4])
      # step 2 with non-zero start: elements at positions 1, 3
      assert Enum.slice(set, 1..3//2) == [2, 4]
      set2 = Xb5.Set.new([1, 2, 3, 4, 5, 6])
      # step 2 from start: elements at positions 0, 2, 4
      assert Enum.slice(set2, 0..4//2) == [1, 3, 5]
    end
  end

  describe "Collectable protocol" do
    test "Enum.into builds set from elements" do
      STU.foreach_test_set(fn _size, ref_elements, _set ->
        result = Enum.into(ref_elements, Xb5.Set.new())
        assert canon_elems(Xb5.Set.to_list(result)) == canon_elems(ref_elements)
      end)
    end

    test "for comprehension with into builds a set" do
      STU.foreach_test_set(fn _size, ref_elements, _set ->
        result = for x <- ref_elements, into: Xb5.Set.new(), do: x
        assert canon_elems(Xb5.Set.to_list(result)) == canon_elems(ref_elements)
      end)
    end

    test "halt branch via Stream.into" do
      result =
        [1, 2, 3, 4, 5]
        |> Stream.into(Xb5.Set.new())
        |> Enum.take(2)

      assert result == [1, 2]
    end
  end

  describe "Inspect protocol" do
    test "inspect produces readable output for all set sizes" do
      STU.foreach_test_set(fn _size, _ref_elements, set ->
        inspected = inspect(set)
        assert String.starts_with?(inspected, "Xb5.Set.new(")
      end)
    end
  end

  defp canon_elems(list), do: Enum.map(list, &TU.canon_element/1)
end
