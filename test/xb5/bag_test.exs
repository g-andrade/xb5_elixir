defmodule Xb5BagTest do
  use ExUnit.Case, async: true
  @moduletag :bag

  alias Xb5BagTestUtils, as: BTU
  alias Xb5TestUtils, as: TU

  doctest Xb5.Bag

  # ---------------------------------------------------------------------------
  # Basic API
  # ---------------------------------------------------------------------------

  describe "construction" do
    test "from enumerable matches element-wise insertion and size" do
      BTU.foreach_tested_size(fn size, ref_elements ->
        bag = Xb5.Bag.new(ref_elements)
        assert canon_list(Xb5.Bag.to_list(bag)) == canon_list(ref_elements)
        assert Xb5.Bag.size(bag) == size

        assert canon_list(Xb5.Bag.to_list(BTU.new_bag_from_each_pushed(ref_elements))) ==
                 canon_list(ref_elements)
      end)
    end
  end

  describe "at" do
    test "returns element at 0-based index, nil if out of bounds" do
      BTU.foreach_test_bag(fn size, ref_elements, bag ->
        for {elem, idx} <- Enum.with_index(ref_elements) do
          assert Xb5.Bag.at(bag, idx) == elem
        end

        assert Xb5.Bag.at(bag, size) == nil
        assert Xb5.Bag.at(bag, size, :missing) == :missing
      end)
    end

    test "supports negative indices" do
      BTU.foreach_test_bag(fn size, ref_elements, bag ->
        if size > 0 do
          for {elem, idx} <- Enum.with_index(ref_elements) do
            assert Xb5.Bag.at(bag, idx - size) == elem
          end
        end

        assert Xb5.Bag.at(bag, -(size + 1)) == nil
      end)
    end
  end

  describe "member?" do
    test "existing elements are found, absent elements are not" do
      BTU.foreach_test_bag(fn size, ref_elements, bag ->
        TU.foreach_existing_element(
          fn elem -> assert Xb5.Bag.member?(bag, elem) end,
          ref_elements,
          size
        )

        TU.foreach_non_existent_element(
          fn elem -> refute Xb5.Bag.member?(bag, elem) end,
          ref_elements,
          100
        )
      end)
    end
  end

  describe "push" do
    test "always grows the bag, even for existing elements" do
      BTU.foreach_test_bag(fn size, ref_elements, bag ->
        TU.foreach_existing_element(
          fn elem ->
            bag2 = Xb5.Bag.push(bag, elem)
            assert Xb5.Bag.size(bag2) == size + 1

            assert canon_list(Xb5.Bag.to_list(bag2)) ==
                     canon_list(TU.add_to_sorted_list(elem, ref_elements))
          end,
          ref_elements,
          min(50, size)
        )

        TU.foreach_non_existent_element(
          fn elem ->
            bag2 = Xb5.Bag.push(bag, elem)
            assert Xb5.Bag.size(bag2) == size + 1

            assert canon_list(Xb5.Bag.to_list(bag2)) ==
                     canon_list(TU.add_to_sorted_list(elem, ref_elements))
          end,
          ref_elements,
          50
        )
      end)
    end
  end

  describe "put" do
    test "adding an existing element is a no-op; adding a new one grows the bag" do
      BTU.foreach_test_bag(fn size, ref_elements, bag ->
        TU.foreach_existing_element(
          fn elem ->
            bag2 = Xb5.Bag.put(bag, elem)
            assert Xb5.Bag.size(bag2) == size
            assert bag2 == bag
          end,
          ref_elements,
          min(50, size)
        )

        TU.foreach_non_existent_element(
          fn elem ->
            bag2 = Xb5.Bag.put(bag, elem)
            assert Xb5.Bag.size(bag2) == size + 1

            assert canon_list(Xb5.Bag.to_list(bag2)) ==
                     canon_list(TU.add_to_sorted_list(elem, ref_elements))
          end,
          ref_elements,
          50
        )
      end)
    end
  end

  describe "delete_sequential" do
    test "deletes elements one by one in order, interleaved with absent-key checks" do
      BTU.foreach_test_bag(fn _size, ref_elements, bag ->
        delete_keys = Enum.map(ref_elements, &TU.randomly_switch_number_type/1)

        {bag_n, []} =
          Enum.reduce(delete_keys, {bag, ref_elements}, fn elem, {bag1, remaining1} ->
            check_delete_absent(bag1, remaining1, 3)

            bag2 = Xb5.Bag.delete(bag1, elem)
            remaining2 = TU.remove_from_sorted_list(elem, remaining1)
            assert canon_list(Xb5.Bag.to_list(bag2)) == canon_list(remaining2)
            assert Xb5.Bag.size(bag2) == length(remaining2)

            {bag2, remaining2}
          end)

        assert Xb5.Bag.to_list(bag_n) == []
        assert Xb5.Bag.size(bag_n) == 0

        check_delete_absent(bag_n, [], 3)
      end)
    end
  end

  describe "delete_shuffled" do
    test "deletes elements in shuffled order, interleaved with absent-key checks" do
      BTU.foreach_test_bag(fn _size, ref_elements, bag ->
        delete_keys =
          ref_elements
          |> TU.list_shuffle()
          |> Enum.map(&TU.randomly_switch_number_type/1)

        {bag_n, []} =
          Enum.reduce(delete_keys, {bag, ref_elements}, fn elem, {bag1, remaining1} ->
            check_delete_absent(bag1, remaining1, 3)

            bag2 = Xb5.Bag.delete(bag1, elem)
            remaining2 = TU.remove_from_sorted_list(elem, remaining1)
            assert canon_list(Xb5.Bag.to_list(bag2)) == canon_list(remaining2)
            assert Xb5.Bag.size(bag2) == length(remaining2)

            {bag2, remaining2}
          end)

        assert Xb5.Bag.to_list(bag_n) == []
        assert Xb5.Bag.size(bag_n) == 0

        check_delete_absent(bag_n, [], 3)
      end)
    end
  end

  describe "delete_all" do
    test "deletes all occurrences of each unique element, interleaved with absent-key checks" do
      BTU.foreach_test_bag(fn _size, ref_elements, bag ->
        delete_keys =
          ref_elements
          |> :lists.usort()
          |> TU.list_shuffle()
          |> Enum.map(&TU.randomly_switch_number_type/1)

        {bag_n, []} =
          Enum.reduce(delete_keys, {bag, ref_elements}, fn elem, {bag1, remaining1} ->
            check_delete_all_absent(bag1, remaining1, 3)

            bag2 = Xb5.Bag.delete_all(bag1, elem)
            remaining2 = TU.remove_all_from_sorted_list(elem, remaining1)
            assert canon_list(Xb5.Bag.to_list(bag2)) == canon_list(remaining2)
            assert Xb5.Bag.size(bag2) == length(remaining2)

            {bag2, remaining2}
          end)

        assert Xb5.Bag.to_list(bag_n) == []
        assert Xb5.Bag.size(bag_n) == 0

        check_delete_all_absent(bag_n, [], 3)
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # first/last/lower/higher
  # ---------------------------------------------------------------------------

  describe "first" do
    test "returns nil (or default) on empty bag, returns first element otherwise" do
      BTU.foreach_test_bag(fn
        0, _ref_elements, bag ->
          assert Xb5.Bag.first(bag) == nil
          assert Xb5.Bag.first(bag, :empty) == :empty

        _size, ref_elements, bag ->
          assert Xb5.Bag.first(bag) == hd(ref_elements)
          assert Xb5.Bag.first(bag, :empty) == hd(ref_elements)
      end)
    end
  end

  describe "first!" do
    test "raises Enum.EmptyError on empty bag, returns first element otherwise" do
      BTU.foreach_test_bag(fn
        0, _ref_elements, bag ->
          assert_raise Enum.EmptyError, fn -> Xb5.Bag.first!(bag) end

        _size, ref_elements, bag ->
          assert Xb5.Bag.first!(bag) == hd(ref_elements)
      end)
    end
  end

  describe "last" do
    test "returns nil (or default) on empty bag, returns last element otherwise" do
      BTU.foreach_test_bag(fn
        0, _ref_elements, bag ->
          assert Xb5.Bag.last(bag) == nil
          assert Xb5.Bag.last(bag, :empty) == :empty

        _size, ref_elements, bag ->
          assert Xb5.Bag.last(bag) == List.last(ref_elements)
          assert Xb5.Bag.last(bag, :empty) == List.last(ref_elements)
      end)
    end
  end

  describe "last!" do
    test "raises Enum.EmptyError on empty bag, returns last element otherwise" do
      BTU.foreach_test_bag(fn
        0, _ref_elements, bag ->
          assert_raise Enum.EmptyError, fn -> Xb5.Bag.last!(bag) end

        _size, ref_elements, bag ->
          assert Xb5.Bag.last!(bag) == List.last(ref_elements)
      end)
    end
  end

  describe "lower" do
    test "returns the largest element strictly less than the given element" do
      BTU.foreach_test_bag(fn _size, ref_elements, bag ->
        unique_ref = :lists.usort(ref_elements)
        run_lower(unique_ref, bag)
      end)
    end
  end

  describe "higher" do
    test "returns the smallest element strictly greater than the given element" do
      BTU.foreach_test_bag(fn _size, ref_elements, bag ->
        unique_ref = :lists.usort(ref_elements)
        run_higher(unique_ref, bag)
      end)
    end
  end

  describe "pop_first!" do
    test "raises Enum.EmptyError on empty bag, pops elements in ascending order" do
      BTU.foreach_test_bag(fn _size, ref_elements, bag ->
        run_pop_first(ref_elements, bag)
      end)
    end
  end

  describe "pop_last!" do
    test "raises Enum.EmptyError on empty bag, pops elements in descending order" do
      BTU.foreach_test_bag(fn _size, ref_elements, bag ->
        run_pop_last(:lists.reverse(ref_elements), bag)
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Order Statistics
  # ---------------------------------------------------------------------------

  describe "count" do
    test "returns the count of each element in the bag" do
      BTU.foreach_test_bag(fn _size, ref_elements, bag ->
        run_count(ref_elements, bag)
      end)
    end
  end

  describe "percentile_inclusive" do
    test "computes inclusive percentile values correctly" do
      BTU.foreach_test_bag(fn size, ref_elements, bag ->
        assert_raise ArgumentError, fn -> Xb5.Bag.percentile(bag, -1) end
        test_valid_percentile_inclusive(size, ref_elements, bag)
      end)
    end
  end

  describe "percentile_exclusive" do
    test "computes exclusive percentile values correctly" do
      BTU.foreach_test_bag(fn size, ref_elements, bag ->
        assert_raise ArgumentError, fn -> Xb5.Bag.percentile(bag, -1, [{:method, :exclusive}]) end
        test_valid_percentile_exclusive(size, ref_elements, bag)
      end)
    end
  end

  describe "percentile_nearest_rank" do
    test "computes nearest_rank percentile values correctly" do
      BTU.foreach_test_bag(fn size, ref_elements, bag ->
        assert_raise ArgumentError, fn ->
          Xb5.Bag.percentile(bag, -1, [{:method, :nearest_rank}])
        end

        test_valid_percentile_nearest_rank(size, ref_elements, bag)
      end)
    end
  end

  describe "percentile_hardcoded1" do
    test "hardcoded [1,2,3,4] percentile values match expected" do
      bag = Xb5.Bag.new([1, 2, 3, 4])
      size = Xb5.Bag.size(bag)
      ref_elements = Xb5.Bag.to_list(bag)

      # Inclusive
      assert canon_equal?(1, inclusive_percentile_rounded(0, bag))
      assert canon_equal?(1.15, inclusive_percentile_rounded(0.05, bag))
      assert canon_equal?(1.3, inclusive_percentile_rounded(0.1, bag))
      assert canon_equal?(1.45, inclusive_percentile_rounded(0.15, bag))
      assert canon_equal?(1.6, inclusive_percentile_rounded(0.2, bag))
      assert canon_equal?(1.75, inclusive_percentile_rounded(0.25, bag))
      assert canon_equal?(1.9, inclusive_percentile_rounded(0.3, bag))
      assert canon_equal?(2.05, inclusive_percentile_rounded(0.35, bag))
      assert canon_equal?(2.2, inclusive_percentile_rounded(0.4, bag))
      assert canon_equal?(2.35, inclusive_percentile_rounded(0.45, bag))
      assert canon_equal?(2.5, inclusive_percentile_rounded(0.5, bag))
      assert canon_equal?(2.65, inclusive_percentile_rounded(0.55, bag))
      assert canon_equal?(2.8, inclusive_percentile_rounded(0.6, bag))
      assert canon_equal?(2.95, inclusive_percentile_rounded(0.65, bag))
      assert canon_equal?(3.1, inclusive_percentile_rounded(0.7, bag))
      assert canon_equal?(3.25, inclusive_percentile_rounded(0.75, bag))
      assert canon_equal?(3.4, inclusive_percentile_rounded(0.8, bag))
      assert canon_equal?(3.55, inclusive_percentile_rounded(0.85, bag))
      assert canon_equal?(3.7, inclusive_percentile_rounded(0.9, bag))
      assert canon_equal?(3.85, inclusive_percentile_rounded(0.95, bag))
      assert canon_equal?(4, inclusive_percentile_rounded(1, bag))

      test_valid_percentile_inclusive(size, ref_elements, bag)

      # Exclusive
      assert canon_equal?(nil, exclusive_percentile_rounded(0.00, bag))
      assert canon_equal?(nil, exclusive_percentile_rounded(0.05, bag))
      assert canon_equal?(nil, exclusive_percentile_rounded(0.10, bag))
      assert canon_equal?(nil, exclusive_percentile_rounded(0.15, bag))
      assert canon_equal?(1, exclusive_percentile_rounded(0.20, bag))
      assert canon_equal?(1.25, exclusive_percentile_rounded(0.25, bag))
      assert canon_equal?(1.5, exclusive_percentile_rounded(0.30, bag))
      assert canon_equal?(1.75, exclusive_percentile_rounded(0.35, bag))
      assert canon_equal?(2, exclusive_percentile_rounded(0.40, bag))
      assert canon_equal?(2.25, exclusive_percentile_rounded(0.45, bag))
      assert canon_equal?(2.5, exclusive_percentile_rounded(0.50, bag))
      assert canon_equal?(2.75, exclusive_percentile_rounded(0.55, bag))
      assert canon_equal?(3, exclusive_percentile_rounded(0.60, bag))
      assert canon_equal?(3.25, exclusive_percentile_rounded(0.65, bag))
      assert canon_equal?(3.5, exclusive_percentile_rounded(0.70, bag))
      assert canon_equal?(3.75, exclusive_percentile_rounded(0.75, bag))
      assert canon_equal?(4, exclusive_percentile_rounded(0.80, bag))
      assert canon_equal?(nil, exclusive_percentile_rounded(0.85, bag))
      assert canon_equal?(nil, exclusive_percentile_rounded(0.90, bag))
      assert canon_equal?(nil, exclusive_percentile_rounded(0.95, bag))
      assert canon_equal?(nil, exclusive_percentile_rounded(1.00, bag))

      test_valid_percentile_exclusive(size, ref_elements, bag)

      # Nearest rank
      assert canon_equal?(nil, Xb5.Bag.percentile(bag, 0.00, [{:method, :nearest_rank}]))
      assert canon_equal?(1, Xb5.Bag.percentile(bag, 0.05, [{:method, :nearest_rank}]))
      assert canon_equal?(1, Xb5.Bag.percentile(bag, 0.1, [{:method, :nearest_rank}]))
      assert canon_equal?(1, Xb5.Bag.percentile(bag, 0.15, [{:method, :nearest_rank}]))
      assert canon_equal?(1, Xb5.Bag.percentile(bag, 0.2, [{:method, :nearest_rank}]))
      assert canon_equal?(1, Xb5.Bag.percentile(bag, 0.25, [{:method, :nearest_rank}]))
      assert canon_equal?(2, Xb5.Bag.percentile(bag, 0.3, [{:method, :nearest_rank}]))
      assert canon_equal?(2, Xb5.Bag.percentile(bag, 0.35, [{:method, :nearest_rank}]))
      assert canon_equal?(2, Xb5.Bag.percentile(bag, 0.4, [{:method, :nearest_rank}]))
      assert canon_equal?(2, Xb5.Bag.percentile(bag, 0.45, [{:method, :nearest_rank}]))
      assert canon_equal?(2, Xb5.Bag.percentile(bag, 0.5, [{:method, :nearest_rank}]))
      assert canon_equal?(3, Xb5.Bag.percentile(bag, 0.55, [{:method, :nearest_rank}]))
      assert canon_equal?(3, Xb5.Bag.percentile(bag, 0.6, [{:method, :nearest_rank}]))
      assert canon_equal?(3, Xb5.Bag.percentile(bag, 0.65, [{:method, :nearest_rank}]))
      assert canon_equal?(3, Xb5.Bag.percentile(bag, 0.7, [{:method, :nearest_rank}]))
      assert canon_equal?(3, Xb5.Bag.percentile(bag, 0.75, [{:method, :nearest_rank}]))
      assert canon_equal?(4, Xb5.Bag.percentile(bag, 0.8, [{:method, :nearest_rank}]))
      assert canon_equal?(4, Xb5.Bag.percentile(bag, 0.85, [{:method, :nearest_rank}]))
      assert canon_equal?(4, Xb5.Bag.percentile(bag, 0.9, [{:method, :nearest_rank}]))
      assert canon_equal?(4, Xb5.Bag.percentile(bag, 0.95, [{:method, :nearest_rank}]))
      assert canon_equal?(4, Xb5.Bag.percentile(bag, 1, [{:method, :nearest_rank}]))

      test_valid_percentile_nearest_rank(size, ref_elements, bag)
    end
  end

  describe "percentile_hardcoded2" do
    test "hardcoded [1,2,3,4,5] percentile values match expected" do
      bag = Xb5.Bag.new([1, 2, 3, 4, 5])
      size = Xb5.Bag.size(bag)
      ref_elements = Xb5.Bag.to_list(bag)

      # Inclusive
      assert canon_equal?(1, inclusive_percentile_rounded(0.00, bag))
      assert canon_equal?(1.2, inclusive_percentile_rounded(0.05, bag))
      assert canon_equal?(1.4, inclusive_percentile_rounded(0.10, bag))
      assert canon_equal?(1.6, inclusive_percentile_rounded(0.15, bag))
      assert canon_equal?(1.8, inclusive_percentile_rounded(0.20, bag))
      assert canon_equal?(2, inclusive_percentile_rounded(0.25, bag))
      assert canon_equal?(2.2, inclusive_percentile_rounded(0.30, bag))
      assert canon_equal?(2.4, inclusive_percentile_rounded(0.35, bag))
      assert canon_equal?(2.6, inclusive_percentile_rounded(0.40, bag))
      assert canon_equal?(2.8, inclusive_percentile_rounded(0.45, bag))
      assert canon_equal?(3, inclusive_percentile_rounded(0.50, bag))
      assert canon_equal?(3.2, inclusive_percentile_rounded(0.55, bag))
      assert canon_equal?(3.4, inclusive_percentile_rounded(0.60, bag))
      assert canon_equal?(3.6, inclusive_percentile_rounded(0.65, bag))
      assert canon_equal?(3.8, inclusive_percentile_rounded(0.70, bag))
      assert canon_equal?(4, inclusive_percentile_rounded(0.75, bag))
      assert canon_equal?(4.2, inclusive_percentile_rounded(0.80, bag))
      assert canon_equal?(4.4, inclusive_percentile_rounded(0.85, bag))
      assert canon_equal?(4.6, inclusive_percentile_rounded(0.90, bag))
      assert canon_equal?(4.8, inclusive_percentile_rounded(0.95, bag))
      assert canon_equal?(5, inclusive_percentile_rounded(1.00, bag))

      test_valid_percentile_inclusive(size, ref_elements, bag)

      # Exclusive
      assert canon_equal?(nil, exclusive_percentile_rounded(0.00, bag))
      assert canon_equal?(nil, exclusive_percentile_rounded(0.05, bag))
      assert canon_equal?(nil, exclusive_percentile_rounded(0.10, bag))
      assert canon_equal?(nil, exclusive_percentile_rounded(0.15, bag))
      assert canon_equal?(1.2, exclusive_percentile_rounded(0.20, bag))
      assert canon_equal?(1.5, exclusive_percentile_rounded(0.25, bag))
      assert canon_equal?(1.8, exclusive_percentile_rounded(0.30, bag))
      assert canon_equal?(2.1, exclusive_percentile_rounded(0.35, bag))
      assert canon_equal?(2.4, exclusive_percentile_rounded(0.40, bag))
      assert canon_equal?(2.7, exclusive_percentile_rounded(0.45, bag))
      assert canon_equal?(3, exclusive_percentile_rounded(0.50, bag))
      assert canon_equal?(3.3, exclusive_percentile_rounded(0.55, bag))
      assert canon_equal?(3.6, exclusive_percentile_rounded(0.60, bag))
      assert canon_equal?(3.9, exclusive_percentile_rounded(0.65, bag))
      assert canon_equal?(4.2, exclusive_percentile_rounded(0.70, bag))
      assert canon_equal?(4.5, exclusive_percentile_rounded(0.75, bag))
      assert canon_equal?(4.8, exclusive_percentile_rounded(0.80, bag))
      assert canon_equal?(nil, exclusive_percentile_rounded(0.85, bag))
      assert canon_equal?(nil, exclusive_percentile_rounded(0.90, bag))
      assert canon_equal?(nil, exclusive_percentile_rounded(0.95, bag))
      assert canon_equal?(nil, exclusive_percentile_rounded(1.00, bag))

      test_valid_percentile_exclusive(size, ref_elements, bag)

      # Nearest rank
      assert canon_equal?(nil, Xb5.Bag.percentile(bag, 0.00, [{:method, :nearest_rank}]))
      assert canon_equal?(1, Xb5.Bag.percentile(bag, 0.05, [{:method, :nearest_rank}]))
      assert canon_equal?(1, Xb5.Bag.percentile(bag, 0.1, [{:method, :nearest_rank}]))
      assert canon_equal?(1, Xb5.Bag.percentile(bag, 0.15, [{:method, :nearest_rank}]))
      assert canon_equal?(1, Xb5.Bag.percentile(bag, 0.2, [{:method, :nearest_rank}]))
      assert canon_equal?(2, Xb5.Bag.percentile(bag, 0.25, [{:method, :nearest_rank}]))
      assert canon_equal?(2, Xb5.Bag.percentile(bag, 0.3, [{:method, :nearest_rank}]))
      assert canon_equal?(2, Xb5.Bag.percentile(bag, 0.35, [{:method, :nearest_rank}]))
      assert canon_equal?(2, Xb5.Bag.percentile(bag, 0.4, [{:method, :nearest_rank}]))
      assert canon_equal?(3, Xb5.Bag.percentile(bag, 0.45, [{:method, :nearest_rank}]))
      assert canon_equal?(3, Xb5.Bag.percentile(bag, 0.5, [{:method, :nearest_rank}]))
      assert canon_equal?(3, Xb5.Bag.percentile(bag, 0.55, [{:method, :nearest_rank}]))
      assert canon_equal?(3, Xb5.Bag.percentile(bag, 0.6, [{:method, :nearest_rank}]))
      assert canon_equal?(4, Xb5.Bag.percentile(bag, 0.65, [{:method, :nearest_rank}]))
      assert canon_equal?(4, Xb5.Bag.percentile(bag, 0.7, [{:method, :nearest_rank}]))
      assert canon_equal?(4, Xb5.Bag.percentile(bag, 0.75, [{:method, :nearest_rank}]))
      assert canon_equal?(4, Xb5.Bag.percentile(bag, 0.8, [{:method, :nearest_rank}]))
      assert canon_equal?(5, Xb5.Bag.percentile(bag, 0.85, [{:method, :nearest_rank}]))
      assert canon_equal?(5, Xb5.Bag.percentile(bag, 0.9, [{:method, :nearest_rank}]))
      assert canon_equal?(5, Xb5.Bag.percentile(bag, 0.95, [{:method, :nearest_rank}]))
      assert canon_equal?(5, Xb5.Bag.percentile(bag, 1, [{:method, :nearest_rank}]))

      test_valid_percentile_nearest_rank(size, ref_elements, bag)
    end
  end

  describe "percentile_hardcoded3" do
    test "hardcoded [1,2,3,4,5,6] percentile values match expected" do
      bag = Xb5.Bag.new([1, 2, 3, 4, 5, 6])
      size = Xb5.Bag.size(bag)
      ref_elements = Xb5.Bag.to_list(bag)

      # Inclusive
      assert canon_equal?(1, inclusive_percentile_rounded(0.00, bag))
      assert canon_equal?(1.25, inclusive_percentile_rounded(0.05, bag))
      assert canon_equal?(1.5, inclusive_percentile_rounded(0.10, bag))
      assert canon_equal?(1.75, inclusive_percentile_rounded(0.15, bag))
      assert canon_equal?(2, inclusive_percentile_rounded(0.20, bag))
      assert canon_equal?(2.25, inclusive_percentile_rounded(0.25, bag))
      assert canon_equal?(2.5, inclusive_percentile_rounded(0.30, bag))
      assert canon_equal?(2.75, inclusive_percentile_rounded(0.35, bag))
      assert canon_equal?(3, inclusive_percentile_rounded(0.40, bag))
      assert canon_equal?(3.25, inclusive_percentile_rounded(0.45, bag))
      assert canon_equal?(3.5, inclusive_percentile_rounded(0.50, bag))
      assert canon_equal?(3.75, inclusive_percentile_rounded(0.55, bag))
      assert canon_equal?(4, inclusive_percentile_rounded(0.60, bag))
      assert canon_equal?(4.25, inclusive_percentile_rounded(0.65, bag))
      assert canon_equal?(4.5, inclusive_percentile_rounded(0.70, bag))
      assert canon_equal?(4.75, inclusive_percentile_rounded(0.75, bag))
      assert canon_equal?(5, inclusive_percentile_rounded(0.80, bag))
      assert canon_equal?(5.25, inclusive_percentile_rounded(0.85, bag))
      assert canon_equal?(5.5, inclusive_percentile_rounded(0.90, bag))
      assert canon_equal?(5.75, inclusive_percentile_rounded(0.95, bag))
      assert canon_equal?(6, inclusive_percentile_rounded(1.00, bag))

      test_valid_percentile_inclusive(size, ref_elements, bag)

      # Exclusive
      assert canon_equal?(nil, exclusive_percentile_rounded(0.00, bag))
      assert canon_equal?(nil, exclusive_percentile_rounded(0.05, bag))
      assert canon_equal?(nil, exclusive_percentile_rounded(0.10, bag))
      assert canon_equal?(1.05, exclusive_percentile_rounded(0.15, bag))
      assert canon_equal?(1.4, exclusive_percentile_rounded(0.20, bag))
      assert canon_equal?(1.75, exclusive_percentile_rounded(0.25, bag))
      assert canon_equal?(2.1, exclusive_percentile_rounded(0.30, bag))
      assert canon_equal?(2.45, exclusive_percentile_rounded(0.35, bag))
      assert canon_equal?(2.8, exclusive_percentile_rounded(0.40, bag))
      assert canon_equal?(3.15, exclusive_percentile_rounded(0.45, bag))
      assert canon_equal?(3.5, exclusive_percentile_rounded(0.50, bag))
      assert canon_equal?(3.85, exclusive_percentile_rounded(0.55, bag))
      assert canon_equal?(4.2, exclusive_percentile_rounded(0.60, bag))
      assert canon_equal?(4.55, exclusive_percentile_rounded(0.65, bag))
      assert canon_equal?(4.9, exclusive_percentile_rounded(0.70, bag))
      assert canon_equal?(5.25, exclusive_percentile_rounded(0.75, bag))
      assert canon_equal?(5.6, exclusive_percentile_rounded(0.80, bag))
      assert canon_equal?(5.95, exclusive_percentile_rounded(0.85, bag))
      assert canon_equal?(nil, exclusive_percentile_rounded(0.90, bag))
      assert canon_equal?(nil, exclusive_percentile_rounded(0.95, bag))
      assert canon_equal?(nil, exclusive_percentile_rounded(1.00, bag))

      test_valid_percentile_exclusive(size, ref_elements, bag)

      # Nearest rank
      assert canon_equal?(nil, Xb5.Bag.percentile(bag, 0.00, [{:method, :nearest_rank}]))
      assert canon_equal?(1, Xb5.Bag.percentile(bag, 0.05, [{:method, :nearest_rank}]))
      assert canon_equal?(1, Xb5.Bag.percentile(bag, 0.1, [{:method, :nearest_rank}]))
      assert canon_equal?(1, Xb5.Bag.percentile(bag, 0.15, [{:method, :nearest_rank}]))
      assert canon_equal?(2, Xb5.Bag.percentile(bag, 0.2, [{:method, :nearest_rank}]))
      assert canon_equal?(2, Xb5.Bag.percentile(bag, 0.25, [{:method, :nearest_rank}]))
      assert canon_equal?(2, Xb5.Bag.percentile(bag, 0.3, [{:method, :nearest_rank}]))
      assert canon_equal?(3, Xb5.Bag.percentile(bag, 0.35, [{:method, :nearest_rank}]))
      assert canon_equal?(3, Xb5.Bag.percentile(bag, 0.4, [{:method, :nearest_rank}]))
      assert canon_equal?(3, Xb5.Bag.percentile(bag, 0.45, [{:method, :nearest_rank}]))
      assert canon_equal?(3, Xb5.Bag.percentile(bag, 0.5, [{:method, :nearest_rank}]))
      assert canon_equal?(4, Xb5.Bag.percentile(bag, 0.55, [{:method, :nearest_rank}]))
      assert canon_equal?(4, Xb5.Bag.percentile(bag, 0.6, [{:method, :nearest_rank}]))
      assert canon_equal?(4, Xb5.Bag.percentile(bag, 0.65, [{:method, :nearest_rank}]))
      assert canon_equal?(5, Xb5.Bag.percentile(bag, 0.7, [{:method, :nearest_rank}]))
      assert canon_equal?(5, Xb5.Bag.percentile(bag, 0.75, [{:method, :nearest_rank}]))
      assert canon_equal?(5, Xb5.Bag.percentile(bag, 0.8, [{:method, :nearest_rank}]))
      assert canon_equal?(6, Xb5.Bag.percentile(bag, 0.85, [{:method, :nearest_rank}]))
      assert canon_equal?(6, Xb5.Bag.percentile(bag, 0.9, [{:method, :nearest_rank}]))
      assert canon_equal?(6, Xb5.Bag.percentile(bag, 0.95, [{:method, :nearest_rank}]))
      assert canon_equal?(6, Xb5.Bag.percentile(bag, 1, [{:method, :nearest_rank}]))

      test_valid_percentile_nearest_rank(size, ref_elements, bag)
    end
  end

  describe "percentile_hardcoded4" do
    test "hardcoded bag with duplicates percentile values match expected" do
      bag = Xb5.Bag.new([1, 1, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 5, 5, 6, 7, 8, 9, 9, 9, 9, 9, 9])
      size = Xb5.Bag.size(bag)
      ref_elements = Xb5.Bag.to_list(bag)

      # Inclusive
      assert canon_equal?(1, inclusive_percentile_rounded(0.00, bag))
      assert canon_equal?(1.1, inclusive_percentile_rounded(0.05, bag))
      assert canon_equal?(2, inclusive_percentile_rounded(0.10, bag))
      assert canon_equal?(2, inclusive_percentile_rounded(0.15, bag))
      assert canon_equal?(2.4, inclusive_percentile_rounded(0.20, bag))
      assert canon_equal?(3, inclusive_percentile_rounded(0.25, bag))
      assert canon_equal?(3, inclusive_percentile_rounded(0.30, bag))
      assert canon_equal?(3, inclusive_percentile_rounded(0.35, bag))
      assert canon_equal?(3.8, inclusive_percentile_rounded(0.40, bag))
      assert canon_equal?(4, inclusive_percentile_rounded(0.45, bag))
      assert canon_equal?(4, inclusive_percentile_rounded(0.50, bag))
      assert canon_equal?(5, inclusive_percentile_rounded(0.55, bag))
      assert canon_equal?(5.2, inclusive_percentile_rounded(0.60, bag))
      assert canon_equal?(6.3, inclusive_percentile_rounded(0.65, bag))
      assert canon_equal?(7.4, inclusive_percentile_rounded(0.70, bag))
      assert canon_equal?(8.5, inclusive_percentile_rounded(0.75, bag))
      assert canon_equal?(9, inclusive_percentile_rounded(0.80, bag))
      assert canon_equal?(9, inclusive_percentile_rounded(0.85, bag))
      assert canon_equal?(9, inclusive_percentile_rounded(0.90, bag))
      assert canon_equal?(9, inclusive_percentile_rounded(0.95, bag))
      assert canon_equal?(9, inclusive_percentile_rounded(1.00, bag))

      test_valid_percentile_inclusive(size, ref_elements, bag)

      # Exclusive
      assert canon_equal?(nil, exclusive_percentile_rounded(0.00, bag))
      assert canon_equal?(1, exclusive_percentile_rounded(0.05, bag))
      assert canon_equal?(1.4, exclusive_percentile_rounded(0.10, bag))
      assert canon_equal?(2, exclusive_percentile_rounded(0.15, bag))
      assert canon_equal?(2, exclusive_percentile_rounded(0.20, bag))
      assert canon_equal?(3, exclusive_percentile_rounded(0.25, bag))
      assert canon_equal?(3, exclusive_percentile_rounded(0.30, bag))
      assert canon_equal?(3, exclusive_percentile_rounded(0.35, bag))
      assert canon_equal?(3.6, exclusive_percentile_rounded(0.40, bag))
      assert canon_equal?(4, exclusive_percentile_rounded(0.45, bag))
      assert canon_equal?(4, exclusive_percentile_rounded(0.50, bag))
      assert canon_equal?(5, exclusive_percentile_rounded(0.55, bag))
      assert canon_equal?(5.4, exclusive_percentile_rounded(0.60, bag))
      assert canon_equal?(6.6, exclusive_percentile_rounded(0.65, bag))
      assert canon_equal?(7.8, exclusive_percentile_rounded(0.70, bag))
      assert canon_equal?(9, exclusive_percentile_rounded(0.75, bag))
      assert canon_equal?(9, exclusive_percentile_rounded(0.80, bag))
      assert canon_equal?(9, exclusive_percentile_rounded(0.85, bag))
      assert canon_equal?(9, exclusive_percentile_rounded(0.90, bag))
      assert canon_equal?(9, exclusive_percentile_rounded(0.95, bag))
      assert canon_equal?(nil, exclusive_percentile_rounded(1.00, bag))

      test_valid_percentile_exclusive(size, ref_elements, bag)

      # Nearest rank
      assert canon_equal?(nil, Xb5.Bag.percentile(bag, 0.00, [{:method, :nearest_rank}]))
      assert canon_equal?(1, Xb5.Bag.percentile(bag, 0.05, [{:method, :nearest_rank}]))
      assert canon_equal?(2, Xb5.Bag.percentile(bag, 0.1, [{:method, :nearest_rank}]))
      assert canon_equal?(2, Xb5.Bag.percentile(bag, 0.15, [{:method, :nearest_rank}]))
      assert canon_equal?(2, Xb5.Bag.percentile(bag, 0.2, [{:method, :nearest_rank}]))
      assert canon_equal?(3, Xb5.Bag.percentile(bag, 0.25, [{:method, :nearest_rank}]))
      assert canon_equal?(3, Xb5.Bag.percentile(bag, 0.3, [{:method, :nearest_rank}]))
      assert canon_equal?(3, Xb5.Bag.percentile(bag, 0.35, [{:method, :nearest_rank}]))
      assert canon_equal?(4, Xb5.Bag.percentile(bag, 0.4, [{:method, :nearest_rank}]))
      assert canon_equal?(4, Xb5.Bag.percentile(bag, 0.45, [{:method, :nearest_rank}]))
      assert canon_equal?(4, Xb5.Bag.percentile(bag, 0.5, [{:method, :nearest_rank}]))
      assert canon_equal?(5, Xb5.Bag.percentile(bag, 0.55, [{:method, :nearest_rank}]))
      assert canon_equal?(5, Xb5.Bag.percentile(bag, 0.6, [{:method, :nearest_rank}]))
      assert canon_equal?(6, Xb5.Bag.percentile(bag, 0.65, [{:method, :nearest_rank}]))
      assert canon_equal?(8, Xb5.Bag.percentile(bag, 0.7, [{:method, :nearest_rank}]))
      assert canon_equal?(9, Xb5.Bag.percentile(bag, 0.75, [{:method, :nearest_rank}]))
      assert canon_equal?(9, Xb5.Bag.percentile(bag, 0.8, [{:method, :nearest_rank}]))
      assert canon_equal?(9, Xb5.Bag.percentile(bag, 0.85, [{:method, :nearest_rank}]))
      assert canon_equal?(9, Xb5.Bag.percentile(bag, 0.9, [{:method, :nearest_rank}]))
      assert canon_equal?(9, Xb5.Bag.percentile(bag, 0.95, [{:method, :nearest_rank}]))
      assert canon_equal?(9, Xb5.Bag.percentile(bag, 1, [{:method, :nearest_rank}]))

      test_valid_percentile_nearest_rank(size, ref_elements, bag)
    end
  end

  describe "percentile_rank" do
    test "computes percentile rank of each element algorithmically" do
      BTU.foreach_test_bag(fn _size, ref_elements, bag ->
        run_percentile_rank(ref_elements, bag)
      end)
    end
  end

  describe "percentile_rank_hardcoded" do
    test "hardcoded percentile rank values match expected" do
      bag1 = Xb5.Bag.new([1, 2, 3, 4])
      list1 = Xb5.Bag.to_list(bag1)

      assert canon_equal?(0.125, percentile_rank_rounded(1, bag1))
      assert canon_equal?(0.375, percentile_rank_rounded(2, bag1))
      assert canon_equal?(0.625, percentile_rank_rounded(3, bag1))
      assert canon_equal?(0.875, percentile_rank_rounded(4, bag1))

      run_percentile_rank(list1, bag1)

      bag2 = Xb5.Bag.new([1, 2, 3, 4, 5])
      list2 = Xb5.Bag.to_list(bag2)

      assert canon_equal?(0.1, percentile_rank_rounded(1, bag2))
      assert canon_equal?(0.3, percentile_rank_rounded(2, bag2))
      assert canon_equal?(0.5, percentile_rank_rounded(3, bag2))
      assert canon_equal?(0.7, percentile_rank_rounded(4, bag2))
      assert canon_equal?(0.9, percentile_rank_rounded(5, bag2))

      run_percentile_rank(list2, bag2)

      bag3 = Xb5.Bag.new([1, 2, 3, 4, 5, 6])
      list3 = Xb5.Bag.to_list(bag3)

      assert canon_equal?(0.0833333333, percentile_rank_rounded(1, bag3))
      assert canon_equal?(0.25, percentile_rank_rounded(2, bag3))
      assert canon_equal?(0.4166666667, percentile_rank_rounded(3, bag3))
      assert canon_equal?(0.5833333333, percentile_rank_rounded(4, bag3))
      assert canon_equal?(0.75, percentile_rank_rounded(5, bag3))
      assert canon_equal?(0.9166666667, percentile_rank_rounded(6, bag3))

      run_percentile_rank(list3, bag3)

      # From Wikipedia article example
      bag4 = Xb5.Bag.new([7, 5, 5, 4, 4, 3, 3, 3, 2, 1])
      list4 = Xb5.Bag.to_list(bag4)

      assert canon_equal?(0.05, percentile_rank_rounded(1, bag4))
      assert canon_equal?(0.15, percentile_rank_rounded(2, bag4))
      assert canon_equal?(0.35, percentile_rank_rounded(3, bag4))
      assert canon_equal?(0.60, percentile_rank_rounded(4, bag4))
      assert canon_equal?(0.80, percentile_rank_rounded(5, bag4))
      assert canon_equal?(0.90, percentile_rank_rounded(6, bag4))
      assert canon_equal?(0.95, percentile_rank_rounded(7, bag4))

      run_percentile_rank(list4, bag4)

      bag5 =
        Xb5.Bag.new([1, 1, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 5, 5, 6, 7, 8, 9, 9, 9, 9, 9, 9])

      list5 = Xb5.Bag.to_list(bag5)

      assert canon_equal?(0.0434782609, percentile_rank_rounded(1, bag5))
      assert canon_equal?(0.152173913, percentile_rank_rounded(2, bag5))
      assert canon_equal?(0.3043478261, percentile_rank_rounded(3, bag5))
      assert canon_equal?(0.4565217391, percentile_rank_rounded(4, bag5))
      assert canon_equal?(0.5652173913, percentile_rank_rounded(5, bag5))
      assert canon_equal?(0.6304347826, percentile_rank_rounded(6, bag5))
      assert canon_equal?(0.6739130435, percentile_rank_rounded(7, bag5))
      assert canon_equal?(0.7173913043, percentile_rank_rounded(8, bag5))
      assert canon_equal?(0.8695652174, percentile_rank_rounded(9, bag5))

      run_percentile_rank(list5, bag5)
    end
  end

  # ---------------------------------------------------------------------------
  # Additional Functions
  # ---------------------------------------------------------------------------

  describe "filter" do
    test "returns a bag with only elements satisfying the predicate" do
      BTU.foreach_test_bag(fn size, ref_elements, bag ->
        run_filter(size, ref_elements, bag)
      end)
    end
  end

  describe "merge" do
    test "merges two bags preserving all duplicates" do
      BTU.foreach_test_bag(fn size, ref_elements, bag ->
        run_merge(size, ref_elements, bag)
      end)
    end
  end

  describe "rewrap" do
    test "round-trips through unwrap!/wrap and rejects invalid inputs" do
      # Invalid inputs
      assert match?({:error, _}, :xb5_bag.unwrap(Xb5.Set.new() |> Xb5.Set.unwrap!()))
      assert match?({:error, _}, :xb5_bag.unwrap(Xb5.Tree.new() |> Xb5.Tree.unwrap!()))

      BTU.foreach_test_bag(fn _size, _ref_elements, bag ->
        unwrapped = Xb5.Bag.unwrap!(bag)
        erlang_bag = :xb5_bag.wrap(unwrapped)
        rewrapped = Xb5.Bag.new(erlang_bag)
        assert Xb5.Bag.to_list(rewrapped) == Xb5.Bag.to_list(bag)
        assert Xb5.Bag.size(rewrapped) == Xb5.Bag.size(bag)
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp check_delete_absent(bag, remaining, amount) when amount > 0 do
    elem = TU.new_element()

    if Enum.any?(remaining, &(&1 == elem)) do
      check_delete_absent(bag, remaining, amount)
    else
      # Xb5.Bag.delete/2 is idempotent — no-op on missing element
      bag2 = Xb5.Bag.delete(bag, elem)
      assert Xb5.Bag.to_list(bag2) == Xb5.Bag.to_list(bag)
      assert Xb5.Bag.size(bag2) == Xb5.Bag.size(bag)
      check_delete_absent(bag, remaining, amount - 1)
    end
  end

  defp check_delete_absent(_bag, _remaining, 0), do: :ok

  defp check_delete_all_absent(bag, remaining, amount) when amount > 0 do
    elem = TU.new_element()

    if Enum.any?(remaining, &(&1 == elem)) do
      check_delete_all_absent(bag, remaining, amount)
    else
      bag2 = Xb5.Bag.delete_all(bag, elem)
      assert bag2 == bag
      check_delete_all_absent(bag, remaining, amount - 1)
    end
  end

  defp check_delete_all_absent(_bag, _remaining, 0), do: :ok

  defp run_lower(unique_ref, bag) do
    case unique_ref do
      [] ->
        elem = TU.new_element()
        assert Xb5.Bag.lower(bag, elem) == :error

      [single] ->
        assert Xb5.Bag.lower(bag, TU.randomly_switch_number_type(single)) == :error

        larger = TU.element_larger(single)
        assert Xb5.Bag.lower(bag, larger) == {:ok, single}

        smaller = TU.element_smaller(single)
        assert Xb5.Bag.lower(bag, smaller) == :error

      [first | next] ->
        assert Xb5.Bag.lower(bag, TU.randomly_switch_number_type(first)) == :error

        smaller = TU.element_smaller(first)
        assert Xb5.Bag.lower(bag, smaller) == :error

        run_lower_recur(first, next, bag)
    end
  end

  defp run_lower_recur(expected, [last], bag) do
    assert canon_equal?(
             {:ok, expected},
             Xb5.Bag.lower(bag, TU.randomly_switch_number_type(last))
           )

    larger = TU.element_larger(last)
    assert larger > last
    assert Xb5.Bag.lower(bag, larger) == {:ok, last}
  end

  defp run_lower_recur(expected, [elem | next], bag) do
    assert Xb5.Bag.lower(bag, TU.randomly_switch_number_type(elem)) == {:ok, expected}

    case TU.element_in_between(expected, elem) do
      {:found, in_between} ->
        assert in_between > expected
        assert in_between < elem
        assert Xb5.Bag.lower(bag, in_between) == {:ok, expected}

      :none ->
        :ok
    end

    run_lower_recur(elem, next, bag)
  end

  defp run_higher(unique_ref, bag) do
    case :lists.reverse(unique_ref) do
      [] ->
        elem = TU.new_element()
        assert Xb5.Bag.higher(bag, elem) == :error

      [single] ->
        assert Xb5.Bag.higher(bag, single) == :error

        larger = TU.element_larger(single)
        assert Xb5.Bag.higher(bag, larger) == :error

        smaller = TU.element_smaller(single)
        assert Xb5.Bag.higher(bag, smaller) == {:ok, single}

      [last | next] ->
        assert Xb5.Bag.higher(bag, TU.randomly_switch_number_type(last)) == :error

        larger = TU.element_larger(last)
        assert Xb5.Bag.higher(bag, larger) == :error

        run_higher_recur(last, next, bag)
    end
  end

  defp run_higher_recur(expected, [first], bag) do
    assert canon_equal?(
             {:ok, expected},
             Xb5.Bag.higher(bag, TU.randomly_switch_number_type(first))
           )

    smaller = TU.element_smaller(first)
    assert smaller < first
    assert Xb5.Bag.higher(bag, smaller) == {:ok, first}
  end

  defp run_higher_recur(expected, [elem | next], bag) do
    assert Xb5.Bag.higher(bag, TU.randomly_switch_number_type(elem)) == {:ok, expected}

    case TU.element_in_between(elem, expected) do
      {:found, in_between} ->
        assert in_between < expected
        assert in_between > elem
        assert Xb5.Bag.higher(bag, in_between) == {:ok, expected}

      :none ->
        :ok
    end

    run_higher_recur(elem, next, bag)
  end

  defp run_pop_first([expected | next], bag) do
    {taken, bag2} = Xb5.Bag.pop_first!(bag)
    assert taken == expected
    assert Xb5.Bag.size(bag2) == length(next)
    run_pop_first(next, bag2)
  end

  defp run_pop_first([], bag) do
    assert_raise Enum.EmptyError, fn -> Xb5.Bag.pop_first!(bag) end
  end

  defp run_pop_last([expected | next], bag) do
    {taken, bag2} = Xb5.Bag.pop_last!(bag)
    assert taken == expected
    assert Xb5.Bag.size(bag2) == length(next)
    run_pop_last(next, bag2)
  end

  defp run_pop_last([], bag) do
    assert_raise Enum.EmptyError, fn -> Xb5.Bag.pop_last!(bag) end
  end

  defp run_count(ref_elements, bag) do
    case ref_elements do
      [] ->
        elem = TU.new_element()
        assert Xb5.Bag.count(bag, elem) == 0

      [first | next] ->
        smaller = TU.element_smaller(first)
        assert Xb5.Bag.count(bag, smaller) == 0
        run_count_recur(first, next, bag)
    end
  end

  defp run_count_recur(elem, tail, bag) do
    {repeated_count, next} = lists_count_and_drop_while(fn e -> e == elem end, tail)
    expected_count = 1 + repeated_count

    assert Xb5.Bag.count(bag, TU.randomly_switch_number_type(elem)) == expected_count

    case next do
      [next_elem | next_tail] ->
        case TU.element_in_between(elem, next_elem) do
          {:found, in_between} ->
            assert Xb5.Bag.count(bag, in_between) == 0

          :none ->
            :ok
        end

        run_count_recur(next_elem, next_tail, bag)

      [] ->
        larger = TU.element_larger(elem)
        assert Xb5.Bag.count(bag, larger) == 0
    end
  end

  defp test_valid_percentile_inclusive(0 = size, _ref_elements, bag) do
    foreach_percentile(
      fn percentile, _low, _high ->
        assert Xb5.Bag.percentile_bracket(bag, percentile) == nil
        assert Xb5.Bag.percentile(bag, percentile) == nil
      end,
      size,
      :inclusive
    )
  end

  defp test_valid_percentile_inclusive(size, ref_elements, bag) do
    foreach_percentile(
      fn percentile, low_rank, high_rank ->
        if low_rank == high_rank do
          exact_elem = Enum.at(ref_elements, low_rank - 1)
          assert canon_equal?({:exact, exact_elem}, Xb5.Bag.percentile_bracket(bag, percentile))
          assert canon_equal?(exact_elem, Xb5.Bag.percentile(bag, percentile))
        else
          case Enum.slice(ref_elements, (low_rank - 1)..(high_rank - 1)) do
            [a, b | _] ->
              if a == b do
                assert canon_equal?(
                         {:exact, a},
                         Xb5.Bag.percentile_bracket(bag, percentile)
                       )

                assert canon_equal?(a, Xb5.Bag.percentile(bag, percentile))
              else
                perc_a = (low_rank - 1) / (size - 1)
                perc_b = (high_rank - 1) / (size - 1)
                perc_range = perc_b - perc_a
                t = (percentile - perc_a) / perc_range

                bracket = Xb5.Bag.percentile_bracket(bag, percentile)

                case bracket do
                  {:between, _low_b, _high_b, _t} ->
                    assert true

                  {:exact, _} ->
                    assert true

                  other ->
                    flunk("Unexpected bracket: #{inspect(other)}")
                end

                if is_number(a) and is_number(b) do
                  result = Xb5.Bag.percentile(bag, percentile)
                  expected = round_float_precision(a + t * (b - a))
                  assert round_float_precision(result) == expected
                end
              end
          end
        end
      end,
      size,
      :inclusive
    )
  end

  defp test_valid_percentile_exclusive(0 = size, _ref_elements, bag) do
    foreach_percentile(
      fn percentile, _low, _high ->
        assert Xb5.Bag.percentile_bracket(bag, percentile, [{:method, :exclusive}]) == nil
        assert Xb5.Bag.percentile(bag, percentile, [{:method, :exclusive}]) == nil
      end,
      size,
      :exclusive
    )
  end

  defp test_valid_percentile_exclusive(size, ref_elements, bag) do
    foreach_percentile(
      fn percentile, low_rank, high_rank ->
        if low_rank < 1 or high_rank > size do
          assert Xb5.Bag.percentile_bracket(bag, percentile, [{:method, :exclusive}]) == nil
          assert Xb5.Bag.percentile(bag, percentile, [{:method, :exclusive}]) == nil
        else
          if low_rank == high_rank do
            exact_elem = Enum.at(ref_elements, low_rank - 1)

            assert canon_equal?(
                     {:exact, exact_elem},
                     Xb5.Bag.percentile_bracket(bag, percentile, [{:method, :exclusive}])
                   )

            assert canon_equal?(
                     exact_elem,
                     Xb5.Bag.percentile(bag, percentile, [{:method, :exclusive}])
                   )
          else
            case Enum.slice(ref_elements, (low_rank - 1)..(high_rank - 1)) do
              [a, b | _] ->
                if a == b do
                  assert canon_equal?(
                           {:exact, a},
                           Xb5.Bag.percentile_bracket(bag, percentile, [{:method, :exclusive}])
                         )

                  assert canon_equal?(
                           a,
                           Xb5.Bag.percentile(bag, percentile, [{:method, :exclusive}])
                         )
                else
                  perc_a = low_rank / (size + 1)
                  perc_b = high_rank / (size + 1)
                  perc_range = perc_b - perc_a
                  t = (percentile - perc_a) / perc_range

                  bracket =
                    Xb5.Bag.percentile_bracket(bag, percentile, [{:method, :exclusive}])

                  case bracket do
                    {:between, _low_b, _high_b, _t} ->
                      assert true

                    {:exact, _} ->
                      assert true

                    other ->
                      flunk("Unexpected bracket: #{inspect(other)}")
                  end

                  if is_number(a) and is_number(b) do
                    result = Xb5.Bag.percentile(bag, percentile, [{:method, :exclusive}])
                    expected = round_float_precision(a + t * (b - a))
                    assert round_float_precision(result) == expected
                  end
                end
            end
          end
        end
      end,
      size,
      :exclusive
    )
  end

  defp test_valid_percentile_nearest_rank(0 = size, _ref_elements, bag) do
    foreach_percentile(
      fn percentile, _low, _high ->
        assert Xb5.Bag.percentile_bracket(bag, percentile, [{:method, :nearest_rank}]) == nil
        assert Xb5.Bag.percentile(bag, percentile, [{:method, :nearest_rank}]) == nil
      end,
      size,
      :nearest_rank
    )
  end

  defp test_valid_percentile_nearest_rank(size, ref_elements, bag) do
    foreach_percentile(
      fn percentile, _low_rank, exact_rank ->
        if exact_rank == 0 do
          assert Xb5.Bag.percentile_bracket(bag, percentile, [{:method, :nearest_rank}]) == nil
          assert Xb5.Bag.percentile(bag, percentile, [{:method, :nearest_rank}]) == nil
        else
          exact_elem = Enum.at(ref_elements, exact_rank - 1)

          assert canon_equal?(
                   {:exact, exact_elem},
                   Xb5.Bag.percentile_bracket(bag, percentile, [{:method, :nearest_rank}])
                 )

          assert canon_equal?(
                   exact_elem,
                   Xb5.Bag.percentile(bag, percentile, [{:method, :nearest_rank}])
                 )
        end
      end,
      size,
      :nearest_rank
    )
  end

  defp foreach_percentile(fun, size, method) do
    for_exact_positions =
      if size > 0 do
        for pos <- 1..size//1, do: pos / size
      else
        []
      end

    max_generic_slice = 100

    for_generic_slices =
      for slice_nr <- 0..max_generic_slice//1, do: slice_nr / max_generic_slice

    percentiles = :lists.usort(for_generic_slices ++ for_exact_positions)

    Enum.each(percentiles, fn percentile ->
      pos = percentile_bracket_pos(percentile, size, method)
      low_rank = floor(pos)
      high_rank = ceil(pos)
      fun.(percentile, low_rank, high_rank)
    end)
  end

  defp percentile_bracket_pos(percentile, size, :inclusive) do
    1 + (size - 1) * percentile
  end

  defp percentile_bracket_pos(percentile, size, :exclusive) do
    (size + 1) * percentile
  end

  defp percentile_bracket_pos(percentile, size, :nearest_rank) do
    ceil(percentile * size)
  end

  defp inclusive_percentile_rounded(percentile, bag) do
    percentile_rounded(percentile, bag, [])
  end

  defp exclusive_percentile_rounded(percentile, bag) do
    percentile_rounded(percentile, bag, [{:method, :exclusive}])
  end

  defp percentile_rounded(percentile, bag, opts) do
    case Xb5.Bag.percentile(bag, percentile, opts) do
      nil -> nil
      value when is_integer(value) -> value
      value when is_float(value) -> round_float_precision(value)
    end
  end

  defp round_float_precision(value) do
    decimals = 10
    factor = :math.pow(10, decimals)
    round(value * factor) / factor
  end

  defp percentile_rank_rounded(elem, bag) do
    round_float_precision(Xb5.Bag.percentile_rank(bag, elem))
  end

  defp run_percentile_rank(ref_elements, bag) do
    case ref_elements do
      [] ->
        assert_raise ArgumentError, fn -> Xb5.Bag.percentile_rank(bag, :foobar) end

      [single] ->
        assert Xb5.Bag.percentile_rank(bag, single) == 0.5
        assert Xb5.Bag.percentile_rank(bag, TU.randomly_switch_number_type(single)) == 0.5

        larger = TU.element_larger(single)
        assert Xb5.Bag.percentile_rank(bag, larger) == 1.0

        smaller = TU.element_smaller(single)
        assert Xb5.Bag.percentile_rank(bag, smaller) == 0.0

      [first | next] ->
        smaller = TU.element_smaller(first)
        assert Xb5.Bag.percentile_rank(bag, smaller) == 0.0

        run_percentile_rank_recur(first, next, 0, length(ref_elements), bag)
    end
  end

  defp run_percentile_rank_recur(elem, next, cf, size, bag) do
    count_repeated = lists_count_while(fn e -> e == elem end, next)
    f = 1 + count_repeated
    updated_cf = cf + f

    elem_rank = (updated_cf - 0.5 * f) / size
    assert Xb5.Bag.percentile_rank(bag, elem) == elem_rank

    rest = Enum.drop(next, count_repeated)

    case rest do
      [next_elem | next_next] ->
        case TU.element_in_between(elem, next_elem) do
          {:found, in_between} ->
            in_between_rank = updated_cf / size
            assert Xb5.Bag.percentile_rank(bag, in_between) == in_between_rank

          :none ->
            :ok
        end

        run_percentile_rank_recur(next_elem, next_next, updated_cf, size, bag)

      [] ->
        larger = TU.element_larger(elem)
        assert Xb5.Bag.percentile_rank(bag, larger) == 1.0
    end
  end

  defp run_filter(size, ref_elements, bag) do
    rough_amounts_to_remove =
      case size do
        0 ->
          [0]

        _ ->
          :lists.usort([
            0,
            1,
            size,
            size - 1,
            :rand.uniform(size),
            :rand.uniform(size),
            :rand.uniform(size)
          ])
      end

    Enum.each(rough_amounts_to_remove, fn rough_amount_to_remove ->
      filter_fun =
        case size do
          0 ->
            fn _e -> true end

          _ ->
            elements_to_remove =
              ref_elements
              |> TU.list_shuffle()
              |> Enum.take(rough_amount_to_remove)

            aux_set = MapSet.new(elements_to_remove, &TU.canon_element/1)
            fn e -> not MapSet.member?(aux_set, TU.canon_element(e)) end
        end

      filtered_bag = Xb5.Bag.filter(bag, filter_fun)

      expected_remaining = Enum.filter(ref_elements, filter_fun)
      assert canon_list(Xb5.Bag.to_list(filtered_bag)) == canon_list(expected_remaining)
      assert Xb5.Bag.size(filtered_bag) == length(expected_remaining)
    end)
  end

  defp run_merge(size, ref_elements, bag) do
    BTU.foreach_second_bag(
      fn ref_elements2, bag2 ->
        merged_bag = Xb5.Bag.merge(bag, bag2)
        expected_merged = :lists.sort(ref_elements ++ ref_elements2)

        assert Xb5.Bag.size(merged_bag) == length(expected_merged)
        assert canon_list(Xb5.Bag.to_list(merged_bag)) == canon_list(expected_merged)
      end,
      size,
      ref_elements
    )
  end

  defp lists_count_while(fun, [h | t]) do
    if fun.(h), do: 1 + lists_count_while(fun, t), else: 0
  end

  defp lists_count_while(_fun, []), do: 0

  defp lists_count_and_drop_while(fun, list), do: lists_count_and_drop_while(fun, list, 0)

  defp lists_count_and_drop_while(fun, [h | t] = l, acc) do
    if fun.(h), do: lists_count_and_drop_while(fun, t, acc + 1), else: {acc, l}
  end

  defp lists_count_and_drop_while(_fun, [], acc), do: {acc, []}

  defp canon_equal?(a, b) do
    TU.canon_element(a) == TU.canon_element(b)
  end

  defp canon_list(list) do
    Enum.map(list, &TU.canon_element/1)
  end

  # ---------------------------------------------------------------------------
  # Protocol coverage
  # ---------------------------------------------------------------------------

  describe "index_of" do
    test "index_of returns 0-based index or nil; index_of! raises on missing" do
      BTU.foreach_test_bag(fn size, ref_elements, bag ->
        TU.foreach_existing_element(
          fn elem ->
            idx = Enum.find_index(ref_elements, fn e -> e == elem end)
            assert Xb5.Bag.index_of(bag, elem) == idx
            assert Xb5.Bag.index_of!(bag, elem) == idx
          end,
          ref_elements,
          min(5, size)
        )

        TU.foreach_non_existent_element(
          fn elem ->
            assert Xb5.Bag.index_of(bag, elem) == nil
            assert_raise KeyError, fn -> Xb5.Bag.index_of!(bag, elem) end
          end,
          ref_elements,
          3
        )
      end)
    end
  end

  describe "new/2 with transform" do
    test "transforms elements before building bag" do
      BTU.foreach_test_bag(fn _size, ref_elements, _bag ->
        transform = fn x -> {x, :transformed} end
        bag2 = Xb5.Bag.new(ref_elements, transform)
        expected = Enum.sort(Enum.map(ref_elements, transform))
        assert Xb5.Bag.size(bag2) == length(ref_elements)
        assert canon_list(Xb5.Bag.to_list(bag2)) == canon_list(expected)
      end)
    end

    test "new/2 with Erlang bag term and transform" do
      base = Xb5.Bag.new([1, 2, 3])
      erlang_bag = :xb5_bag.wrap(Xb5.Bag.unwrap!(base))
      bag = Xb5.Bag.new(erlang_bag, fn x -> x * 2 end)
      assert Xb5.Bag.to_list(bag) == [2, 4, 6]
    end
  end

  describe "reject" do
    test "keeps elements for which fun returns falsy" do
      BTU.foreach_test_bag(fn _size, ref_elements, bag ->
        pred = fn x -> rem(:erlang.phash2(TU.canon_element(x)), 2) == 0 end
        bag2 = Xb5.Bag.reject(bag, pred)
        expected = Enum.reject(ref_elements, pred)
        assert Xb5.Bag.size(bag2) == length(expected)
        assert canon_list(Xb5.Bag.to_list(bag2)) == canon_list(expected)
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Stream API
  # ---------------------------------------------------------------------------

  describe "stream" do
    test "asc matches to_list" do
      BTU.foreach_test_bag(fn size, ref_elements, bag ->
        result = Xb5.Bag.stream(bag) |> Enum.to_list()
        assert canon_list(result) == canon_list(ref_elements)
        assert length(result) == size
      end)
    end

    test "desc matches desc to_list" do
      BTU.foreach_test_bag(fn size, ref_elements, bag ->
        result = Xb5.Bag.stream(bag, :desc) |> Enum.to_list()
        assert canon_list(result) == canon_list(Enum.reverse(ref_elements))
        assert length(result) == size
      end)
    end

    test "partial consumption via Enum.take" do
      BTU.foreach_test_bag(fn size, ref_elements, bag ->
        if size >= 2 do
          take = div(size, 2)
          result = Xb5.Bag.stream(bag) |> Enum.take(take)
          assert canon_list(result) == canon_list(Enum.take(ref_elements, take))
        end
      end)
    end
  end

  describe "stream_from" do
    test "asc: multiple sampled existing elements as start points" do
      BTU.foreach_test_bag(fn size, ref_elements, bag ->
        if size > 0 do
          ref_elements
          |> TU.list_shuffle()
          |> Enum.take(10)
          |> Enum.each(fn start_elem ->
            result = Xb5.Bag.stream_from(bag, start_elem) |> Enum.to_list()
            expected = Enum.drop_while(ref_elements, fn e -> e < start_elem end)
            assert canon_list(result) == canon_list(expected)
          end)
        end
      end)
    end

    test "asc: starting below all elements yields full stream" do
      BTU.foreach_test_bag(fn size, ref_elements, bag ->
        if size > 0 do
          before_all = TU.element_smaller(hd(ref_elements))
          result = Xb5.Bag.stream_from(bag, before_all) |> Enum.to_list()
          assert canon_list(result) == canon_list(ref_elements)
        end
      end)
    end

    test "asc: starting above all elements yields empty stream" do
      BTU.foreach_test_bag(fn size, ref_elements, bag ->
        if size > 0 do
          after_all = TU.element_larger(List.last(ref_elements))
          assert Xb5.Bag.stream_from(bag, after_all) |> Enum.to_list() == []
        end
      end)
    end

    test "desc: multiple sampled existing elements as start points" do
      BTU.foreach_test_bag(fn size, ref_elements, bag ->
        if size > 0 do
          ref_elements
          |> TU.list_shuffle()
          |> Enum.take(10)
          |> Enum.each(fn start_elem ->
            result = Xb5.Bag.stream_from(bag, start_elem, :desc) |> Enum.to_list()

            expected =
              ref_elements |> Enum.take_while(fn e -> e <= start_elem end) |> Enum.reverse()

            assert canon_list(result) == canon_list(expected)
          end)
        end
      end)
    end

    test "desc: starting above all elements yields full desc stream" do
      BTU.foreach_test_bag(fn size, ref_elements, bag ->
        if size > 0 do
          after_all = TU.element_larger(List.last(ref_elements))
          result = Xb5.Bag.stream_from(bag, after_all, :desc) |> Enum.to_list()
          assert canon_list(result) == canon_list(Enum.reverse(ref_elements))
        end
      end)
    end

    test "desc: starting below all elements yields empty stream" do
      BTU.foreach_test_bag(fn size, ref_elements, bag ->
        if size > 0 do
          before_all = TU.element_smaller(hd(ref_elements))
          assert Xb5.Bag.stream_from(bag, before_all, :desc) |> Enum.to_list() == []
        end
      end)
    end
  end

  describe "stream_from_index" do
    test "multiple sampled valid positive indices yield correct suffix" do
      BTU.foreach_test_bag(fn size, ref_elements, bag ->
        if size > 0 do
          for(_ <- 1..min(10, size)//1, do: :rand.uniform(size) - 1)
          |> Enum.each(fn idx ->
            result = Xb5.Bag.stream_from_index(bag, idx) |> Enum.to_list()
            assert canon_list(result) == canon_list(Enum.drop(ref_elements, idx))
            assert length(result) == size - idx
          end)
        end
      end)
    end

    test "multiple sampled valid negative indices yield correct suffix" do
      BTU.foreach_test_bag(fn size, ref_elements, bag ->
        if size > 0 do
          for(_ <- 1..min(10, size)//1, do: -:rand.uniform(size))
          |> Enum.each(fn idx ->
            result = Xb5.Bag.stream_from_index(bag, idx) |> Enum.to_list()
            assert canon_list(result) == canon_list(Enum.drop(ref_elements, size + idx))
            assert length(result) == -idx
          end)
        end
      end)
    end

    test "out-of-bounds indices yield empty stream" do
      BTU.foreach_test_bag(fn size, _ref_elements, bag ->
        assert Xb5.Bag.stream_from_index(bag, size) |> Enum.to_list() == []
        assert Xb5.Bag.stream_from_index(bag, -(size + 1)) |> Enum.to_list() == []
      end)
    end

    test "partial consumption from a sampled index" do
      BTU.foreach_test_bag(fn size, ref_elements, bag ->
        if size >= 4 do
          idx = :rand.uniform(size - 1) - 1
          take = :rand.uniform(size - idx)
          result = Xb5.Bag.stream_from_index(bag, idx) |> Enum.take(take)
          expected = ref_elements |> Enum.drop(idx) |> Enum.take(take)
          assert canon_list(result) == canon_list(expected)
        end
      end)
    end
  end

  describe "Enumerable protocol" do
    test "count, member?, reduce, and slice" do
      BTU.foreach_test_bag(fn size, ref_elements, bag ->
        assert Enum.count(bag) == size

        TU.foreach_existing_element(
          fn elem ->
            assert Enum.member?(bag, elem)
          end,
          ref_elements,
          min(5, size)
        )

        TU.foreach_non_existent_element(
          fn elem ->
            refute Enum.member?(bag, elem)
          end,
          ref_elements,
          3
        )

        assert canon_list(Enum.to_list(bag)) == canon_list(ref_elements)

        if size >= 2 do
          slice_start = div(size, 4)
          slice_len = max(1, div(size, 2))
          sliced = Enum.slice(bag, slice_start, slice_len)
          expected_slice = Enum.slice(ref_elements, slice_start, slice_len)
          assert canon_list(sliced) == canon_list(expected_slice)
        end
      end)
    end

    test "Enum.slice with step exercises step branches" do
      bag = Xb5.Bag.new([1, 2, 3, 4, 5, 6])
      # step 2: elements at positions 0, 2, 4
      assert Enum.slice(bag, 0..4//2) == [1, 3, 5]
    end
  end

  describe "Collectable protocol" do
    test "Enum.into builds bag from elements" do
      BTU.foreach_test_bag(fn _size, ref_elements, _bag ->
        result = Enum.into(ref_elements, Xb5.Bag.new())
        assert canon_list(Xb5.Bag.to_list(result)) == canon_list(ref_elements)
      end)
    end

    test "for comprehension with into builds a bag" do
      BTU.foreach_test_bag(fn _size, ref_elements, _bag ->
        result = for x <- ref_elements, into: Xb5.Bag.new(), do: x
        assert canon_list(Xb5.Bag.to_list(result)) == canon_list(ref_elements)
      end)
    end

    test "halt branch via Stream.into" do
      result =
        [1, 2, 3, 4, 5]
        |> Stream.into(Xb5.Bag.new())
        |> Enum.take(2)

      assert result == [1, 2]
    end
  end

  describe "Inspect protocol" do
    test "inspect produces readable output for all bag sizes" do
      BTU.foreach_test_bag(fn _size, _ref_elements, bag ->
        inspected = inspect(bag)
        assert String.starts_with?(inspected, "Xb5.Bag.new(")
      end)
    end
  end
end
