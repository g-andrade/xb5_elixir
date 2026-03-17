defmodule Xb5BagTest do
  use ExUnit.Case, async: true
  alias Xb5BagTestUtils, as: BTU
  alias Xb5TestUtils, as: TU

  # ---------------------------------------------------------------------------
  # Basic API
  # ---------------------------------------------------------------------------

  describe "construction" do
    test "from enumerable matches element-wise insertion and size" do
      BTU.foreach_tested_size(fn size, ref_elements ->
        bag = Xb5.Bag.new(ref_elements)
        assert canon_list(Xb5.Bag.to_list(bag)) == canon_list(ref_elements)
        assert Xb5.Bag.size(bag) == size

        assert canon_list(Xb5.Bag.to_list(BTU.new_bag_from_each_added(ref_elements))) ==
                 canon_list(ref_elements)
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

  describe "add" do
    test "always grows the bag, even for existing elements" do
      BTU.foreach_test_bag(fn size, ref_elements, bag ->
        TU.foreach_existing_element(
          fn elem ->
            bag2 = Xb5.Bag.add(bag, elem)
            assert Xb5.Bag.size(bag2) == size + 1

            assert canon_list(Xb5.Bag.to_list(bag2)) ==
                     canon_list(TU.add_to_sorted_list(elem, ref_elements))
          end,
          ref_elements,
          min(50, size)
        )

        TU.foreach_non_existent_element(
          fn elem ->
            bag2 = Xb5.Bag.add(bag, elem)
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
    test "putting an existing element is a no-op; putting a new one grows the bag" do
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

  # ---------------------------------------------------------------------------
  # Smaller and Larger
  # ---------------------------------------------------------------------------

  describe "smallest!" do
    test "raises ArgumentError on empty bag, returns smallest element otherwise" do
      BTU.foreach_test_bag(fn
        0, _ref_elements, bag ->
          assert_raise ArgumentError, fn -> Xb5.Bag.smallest!(bag) end

        _size, ref_elements, bag ->
          assert Xb5.Bag.smallest!(bag) == hd(ref_elements)
      end)
    end
  end

  describe "largest!" do
    test "raises ArgumentError on empty bag, returns largest element otherwise" do
      BTU.foreach_test_bag(fn
        0, _ref_elements, bag ->
          assert_raise ArgumentError, fn -> Xb5.Bag.largest!(bag) end

        _size, ref_elements, bag ->
          assert Xb5.Bag.largest!(bag) == List.last(ref_elements)
      end)
    end
  end

  describe "smaller" do
    test "returns the largest element strictly less than the given element" do
      BTU.foreach_test_bag(fn _size, ref_elements, bag ->
        unique_ref = :lists.usort(ref_elements)
        run_smaller(unique_ref, bag)
      end)
    end
  end

  describe "larger" do
    test "returns the smallest element strictly greater than the given element" do
      BTU.foreach_test_bag(fn _size, ref_elements, bag ->
        unique_ref = :lists.usort(ref_elements)
        run_larger(unique_ref, bag)
      end)
    end
  end

  describe "pop_smallest!" do
    test "raises ArgumentError on empty bag, pops elements in ascending order" do
      BTU.foreach_test_bag(fn _size, ref_elements, bag ->
        run_pop_smallest(ref_elements, bag)
      end)
    end
  end

  describe "pop_largest!" do
    test "raises ArgumentError on empty bag, pops elements in descending order" do
      BTU.foreach_test_bag(fn _size, ref_elements, bag ->
        run_pop_largest(:lists.reverse(ref_elements), bag)
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
      assert canon_equal?({:value, 1}, inclusive_percentile_rounded(0, bag))
      assert canon_equal?({:value, 1.15}, inclusive_percentile_rounded(0.05, bag))
      assert canon_equal?({:value, 1.3}, inclusive_percentile_rounded(0.1, bag))
      assert canon_equal?({:value, 1.45}, inclusive_percentile_rounded(0.15, bag))
      assert canon_equal?({:value, 1.6}, inclusive_percentile_rounded(0.2, bag))
      assert canon_equal?({:value, 1.75}, inclusive_percentile_rounded(0.25, bag))
      assert canon_equal?({:value, 1.9}, inclusive_percentile_rounded(0.3, bag))
      assert canon_equal?({:value, 2.05}, inclusive_percentile_rounded(0.35, bag))
      assert canon_equal?({:value, 2.2}, inclusive_percentile_rounded(0.4, bag))
      assert canon_equal?({:value, 2.35}, inclusive_percentile_rounded(0.45, bag))
      assert canon_equal?({:value, 2.5}, inclusive_percentile_rounded(0.5, bag))
      assert canon_equal?({:value, 2.65}, inclusive_percentile_rounded(0.55, bag))
      assert canon_equal?({:value, 2.8}, inclusive_percentile_rounded(0.6, bag))
      assert canon_equal?({:value, 2.95}, inclusive_percentile_rounded(0.65, bag))
      assert canon_equal?({:value, 3.1}, inclusive_percentile_rounded(0.7, bag))
      assert canon_equal?({:value, 3.25}, inclusive_percentile_rounded(0.75, bag))
      assert canon_equal?({:value, 3.4}, inclusive_percentile_rounded(0.8, bag))
      assert canon_equal?({:value, 3.55}, inclusive_percentile_rounded(0.85, bag))
      assert canon_equal?({:value, 3.7}, inclusive_percentile_rounded(0.9, bag))
      assert canon_equal?({:value, 3.85}, inclusive_percentile_rounded(0.95, bag))
      assert canon_equal?({:value, 4}, inclusive_percentile_rounded(1, bag))

      test_valid_percentile_inclusive(size, ref_elements, bag)

      # Exclusive
      assert canon_equal?(:none, exclusive_percentile_rounded(0.00, bag))
      assert canon_equal?(:none, exclusive_percentile_rounded(0.05, bag))
      assert canon_equal?(:none, exclusive_percentile_rounded(0.10, bag))
      assert canon_equal?(:none, exclusive_percentile_rounded(0.15, bag))
      assert canon_equal?({:value, 1}, exclusive_percentile_rounded(0.20, bag))
      assert canon_equal?({:value, 1.25}, exclusive_percentile_rounded(0.25, bag))
      assert canon_equal?({:value, 1.5}, exclusive_percentile_rounded(0.30, bag))
      assert canon_equal?({:value, 1.75}, exclusive_percentile_rounded(0.35, bag))
      assert canon_equal?({:value, 2}, exclusive_percentile_rounded(0.40, bag))
      assert canon_equal?({:value, 2.25}, exclusive_percentile_rounded(0.45, bag))
      assert canon_equal?({:value, 2.5}, exclusive_percentile_rounded(0.50, bag))
      assert canon_equal?({:value, 2.75}, exclusive_percentile_rounded(0.55, bag))
      assert canon_equal?({:value, 3}, exclusive_percentile_rounded(0.60, bag))
      assert canon_equal?({:value, 3.25}, exclusive_percentile_rounded(0.65, bag))
      assert canon_equal?({:value, 3.5}, exclusive_percentile_rounded(0.70, bag))
      assert canon_equal?({:value, 3.75}, exclusive_percentile_rounded(0.75, bag))
      assert canon_equal?({:value, 4}, exclusive_percentile_rounded(0.80, bag))
      assert canon_equal?(:none, exclusive_percentile_rounded(0.85, bag))
      assert canon_equal?(:none, exclusive_percentile_rounded(0.90, bag))
      assert canon_equal?(:none, exclusive_percentile_rounded(0.95, bag))
      assert canon_equal?(:none, exclusive_percentile_rounded(1.00, bag))

      test_valid_percentile_exclusive(size, ref_elements, bag)

      # Nearest rank
      assert canon_equal?(:none, Xb5.Bag.percentile(bag, 0.00, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 1}, Xb5.Bag.percentile(bag, 0.05, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 1}, Xb5.Bag.percentile(bag, 0.1, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 1}, Xb5.Bag.percentile(bag, 0.15, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 1}, Xb5.Bag.percentile(bag, 0.2, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 1}, Xb5.Bag.percentile(bag, 0.25, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 2}, Xb5.Bag.percentile(bag, 0.3, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 2}, Xb5.Bag.percentile(bag, 0.35, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 2}, Xb5.Bag.percentile(bag, 0.4, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 2}, Xb5.Bag.percentile(bag, 0.45, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 2}, Xb5.Bag.percentile(bag, 0.5, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 3}, Xb5.Bag.percentile(bag, 0.55, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 3}, Xb5.Bag.percentile(bag, 0.6, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 3}, Xb5.Bag.percentile(bag, 0.65, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 3}, Xb5.Bag.percentile(bag, 0.7, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 3}, Xb5.Bag.percentile(bag, 0.75, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 4}, Xb5.Bag.percentile(bag, 0.8, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 4}, Xb5.Bag.percentile(bag, 0.85, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 4}, Xb5.Bag.percentile(bag, 0.9, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 4}, Xb5.Bag.percentile(bag, 0.95, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 4}, Xb5.Bag.percentile(bag, 1, [{:method, :nearest_rank}]))

      test_valid_percentile_nearest_rank(size, ref_elements, bag)
    end
  end

  describe "percentile_hardcoded2" do
    test "hardcoded [1,2,3,4,5] percentile values match expected" do
      bag = Xb5.Bag.new([1, 2, 3, 4, 5])
      size = Xb5.Bag.size(bag)
      ref_elements = Xb5.Bag.to_list(bag)

      # Inclusive
      assert canon_equal?({:value, 1}, inclusive_percentile_rounded(0.00, bag))
      assert canon_equal?({:value, 1.2}, inclusive_percentile_rounded(0.05, bag))
      assert canon_equal?({:value, 1.4}, inclusive_percentile_rounded(0.10, bag))
      assert canon_equal?({:value, 1.6}, inclusive_percentile_rounded(0.15, bag))
      assert canon_equal?({:value, 1.8}, inclusive_percentile_rounded(0.20, bag))
      assert canon_equal?({:value, 2}, inclusive_percentile_rounded(0.25, bag))
      assert canon_equal?({:value, 2.2}, inclusive_percentile_rounded(0.30, bag))
      assert canon_equal?({:value, 2.4}, inclusive_percentile_rounded(0.35, bag))
      assert canon_equal?({:value, 2.6}, inclusive_percentile_rounded(0.40, bag))
      assert canon_equal?({:value, 2.8}, inclusive_percentile_rounded(0.45, bag))
      assert canon_equal?({:value, 3}, inclusive_percentile_rounded(0.50, bag))
      assert canon_equal?({:value, 3.2}, inclusive_percentile_rounded(0.55, bag))
      assert canon_equal?({:value, 3.4}, inclusive_percentile_rounded(0.60, bag))
      assert canon_equal?({:value, 3.6}, inclusive_percentile_rounded(0.65, bag))
      assert canon_equal?({:value, 3.8}, inclusive_percentile_rounded(0.70, bag))
      assert canon_equal?({:value, 4}, inclusive_percentile_rounded(0.75, bag))
      assert canon_equal?({:value, 4.2}, inclusive_percentile_rounded(0.80, bag))
      assert canon_equal?({:value, 4.4}, inclusive_percentile_rounded(0.85, bag))
      assert canon_equal?({:value, 4.6}, inclusive_percentile_rounded(0.90, bag))
      assert canon_equal?({:value, 4.8}, inclusive_percentile_rounded(0.95, bag))
      assert canon_equal?({:value, 5}, inclusive_percentile_rounded(1.00, bag))

      test_valid_percentile_inclusive(size, ref_elements, bag)

      # Exclusive
      assert canon_equal?(:none, exclusive_percentile_rounded(0.00, bag))
      assert canon_equal?(:none, exclusive_percentile_rounded(0.05, bag))
      assert canon_equal?(:none, exclusive_percentile_rounded(0.10, bag))
      assert canon_equal?(:none, exclusive_percentile_rounded(0.15, bag))
      assert canon_equal?({:value, 1.2}, exclusive_percentile_rounded(0.20, bag))
      assert canon_equal?({:value, 1.5}, exclusive_percentile_rounded(0.25, bag))
      assert canon_equal?({:value, 1.8}, exclusive_percentile_rounded(0.30, bag))
      assert canon_equal?({:value, 2.1}, exclusive_percentile_rounded(0.35, bag))
      assert canon_equal?({:value, 2.4}, exclusive_percentile_rounded(0.40, bag))
      assert canon_equal?({:value, 2.7}, exclusive_percentile_rounded(0.45, bag))
      assert canon_equal?({:value, 3}, exclusive_percentile_rounded(0.50, bag))
      assert canon_equal?({:value, 3.3}, exclusive_percentile_rounded(0.55, bag))
      assert canon_equal?({:value, 3.6}, exclusive_percentile_rounded(0.60, bag))
      assert canon_equal?({:value, 3.9}, exclusive_percentile_rounded(0.65, bag))
      assert canon_equal?({:value, 4.2}, exclusive_percentile_rounded(0.70, bag))
      assert canon_equal?({:value, 4.5}, exclusive_percentile_rounded(0.75, bag))
      assert canon_equal?({:value, 4.8}, exclusive_percentile_rounded(0.80, bag))
      assert canon_equal?(:none, exclusive_percentile_rounded(0.85, bag))
      assert canon_equal?(:none, exclusive_percentile_rounded(0.90, bag))
      assert canon_equal?(:none, exclusive_percentile_rounded(0.95, bag))
      assert canon_equal?(:none, exclusive_percentile_rounded(1.00, bag))

      test_valid_percentile_exclusive(size, ref_elements, bag)

      # Nearest rank
      assert canon_equal?(:none, Xb5.Bag.percentile(bag, 0.00, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 1}, Xb5.Bag.percentile(bag, 0.05, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 1}, Xb5.Bag.percentile(bag, 0.1, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 1}, Xb5.Bag.percentile(bag, 0.15, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 1}, Xb5.Bag.percentile(bag, 0.2, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 2}, Xb5.Bag.percentile(bag, 0.25, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 2}, Xb5.Bag.percentile(bag, 0.3, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 2}, Xb5.Bag.percentile(bag, 0.35, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 2}, Xb5.Bag.percentile(bag, 0.4, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 3}, Xb5.Bag.percentile(bag, 0.45, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 3}, Xb5.Bag.percentile(bag, 0.5, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 3}, Xb5.Bag.percentile(bag, 0.55, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 3}, Xb5.Bag.percentile(bag, 0.6, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 4}, Xb5.Bag.percentile(bag, 0.65, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 4}, Xb5.Bag.percentile(bag, 0.7, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 4}, Xb5.Bag.percentile(bag, 0.75, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 4}, Xb5.Bag.percentile(bag, 0.8, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 5}, Xb5.Bag.percentile(bag, 0.85, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 5}, Xb5.Bag.percentile(bag, 0.9, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 5}, Xb5.Bag.percentile(bag, 0.95, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 5}, Xb5.Bag.percentile(bag, 1, [{:method, :nearest_rank}]))

      test_valid_percentile_nearest_rank(size, ref_elements, bag)
    end
  end

  describe "percentile_hardcoded3" do
    test "hardcoded [1,2,3,4,5,6] percentile values match expected" do
      bag = Xb5.Bag.new([1, 2, 3, 4, 5, 6])
      size = Xb5.Bag.size(bag)
      ref_elements = Xb5.Bag.to_list(bag)

      # Inclusive
      assert canon_equal?({:value, 1}, inclusive_percentile_rounded(0.00, bag))
      assert canon_equal?({:value, 1.25}, inclusive_percentile_rounded(0.05, bag))
      assert canon_equal?({:value, 1.5}, inclusive_percentile_rounded(0.10, bag))
      assert canon_equal?({:value, 1.75}, inclusive_percentile_rounded(0.15, bag))
      assert canon_equal?({:value, 2}, inclusive_percentile_rounded(0.20, bag))
      assert canon_equal?({:value, 2.25}, inclusive_percentile_rounded(0.25, bag))
      assert canon_equal?({:value, 2.5}, inclusive_percentile_rounded(0.30, bag))
      assert canon_equal?({:value, 2.75}, inclusive_percentile_rounded(0.35, bag))
      assert canon_equal?({:value, 3}, inclusive_percentile_rounded(0.40, bag))
      assert canon_equal?({:value, 3.25}, inclusive_percentile_rounded(0.45, bag))
      assert canon_equal?({:value, 3.5}, inclusive_percentile_rounded(0.50, bag))
      assert canon_equal?({:value, 3.75}, inclusive_percentile_rounded(0.55, bag))
      assert canon_equal?({:value, 4}, inclusive_percentile_rounded(0.60, bag))
      assert canon_equal?({:value, 4.25}, inclusive_percentile_rounded(0.65, bag))
      assert canon_equal?({:value, 4.5}, inclusive_percentile_rounded(0.70, bag))
      assert canon_equal?({:value, 4.75}, inclusive_percentile_rounded(0.75, bag))
      assert canon_equal?({:value, 5}, inclusive_percentile_rounded(0.80, bag))
      assert canon_equal?({:value, 5.25}, inclusive_percentile_rounded(0.85, bag))
      assert canon_equal?({:value, 5.5}, inclusive_percentile_rounded(0.90, bag))
      assert canon_equal?({:value, 5.75}, inclusive_percentile_rounded(0.95, bag))
      assert canon_equal?({:value, 6}, inclusive_percentile_rounded(1.00, bag))

      test_valid_percentile_inclusive(size, ref_elements, bag)

      # Exclusive
      assert canon_equal?(:none, exclusive_percentile_rounded(0.00, bag))
      assert canon_equal?(:none, exclusive_percentile_rounded(0.05, bag))
      assert canon_equal?(:none, exclusive_percentile_rounded(0.10, bag))
      assert canon_equal?({:value, 1.05}, exclusive_percentile_rounded(0.15, bag))
      assert canon_equal?({:value, 1.4}, exclusive_percentile_rounded(0.20, bag))
      assert canon_equal?({:value, 1.75}, exclusive_percentile_rounded(0.25, bag))
      assert canon_equal?({:value, 2.1}, exclusive_percentile_rounded(0.30, bag))
      assert canon_equal?({:value, 2.45}, exclusive_percentile_rounded(0.35, bag))
      assert canon_equal?({:value, 2.8}, exclusive_percentile_rounded(0.40, bag))
      assert canon_equal?({:value, 3.15}, exclusive_percentile_rounded(0.45, bag))
      assert canon_equal?({:value, 3.5}, exclusive_percentile_rounded(0.50, bag))
      assert canon_equal?({:value, 3.85}, exclusive_percentile_rounded(0.55, bag))
      assert canon_equal?({:value, 4.2}, exclusive_percentile_rounded(0.60, bag))
      assert canon_equal?({:value, 4.55}, exclusive_percentile_rounded(0.65, bag))
      assert canon_equal?({:value, 4.9}, exclusive_percentile_rounded(0.70, bag))
      assert canon_equal?({:value, 5.25}, exclusive_percentile_rounded(0.75, bag))
      assert canon_equal?({:value, 5.6}, exclusive_percentile_rounded(0.80, bag))
      assert canon_equal?({:value, 5.95}, exclusive_percentile_rounded(0.85, bag))
      assert canon_equal?(:none, exclusive_percentile_rounded(0.90, bag))
      assert canon_equal?(:none, exclusive_percentile_rounded(0.95, bag))
      assert canon_equal?(:none, exclusive_percentile_rounded(1.00, bag))

      test_valid_percentile_exclusive(size, ref_elements, bag)

      # Nearest rank
      assert canon_equal?(:none, Xb5.Bag.percentile(bag, 0.00, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 1}, Xb5.Bag.percentile(bag, 0.05, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 1}, Xb5.Bag.percentile(bag, 0.1, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 1}, Xb5.Bag.percentile(bag, 0.15, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 2}, Xb5.Bag.percentile(bag, 0.2, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 2}, Xb5.Bag.percentile(bag, 0.25, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 2}, Xb5.Bag.percentile(bag, 0.3, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 3}, Xb5.Bag.percentile(bag, 0.35, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 3}, Xb5.Bag.percentile(bag, 0.4, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 3}, Xb5.Bag.percentile(bag, 0.45, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 3}, Xb5.Bag.percentile(bag, 0.5, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 4}, Xb5.Bag.percentile(bag, 0.55, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 4}, Xb5.Bag.percentile(bag, 0.6, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 4}, Xb5.Bag.percentile(bag, 0.65, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 5}, Xb5.Bag.percentile(bag, 0.7, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 5}, Xb5.Bag.percentile(bag, 0.75, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 5}, Xb5.Bag.percentile(bag, 0.8, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 6}, Xb5.Bag.percentile(bag, 0.85, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 6}, Xb5.Bag.percentile(bag, 0.9, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 6}, Xb5.Bag.percentile(bag, 0.95, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 6}, Xb5.Bag.percentile(bag, 1, [{:method, :nearest_rank}]))

      test_valid_percentile_nearest_rank(size, ref_elements, bag)
    end
  end

  describe "percentile_hardcoded4" do
    test "hardcoded bag with duplicates percentile values match expected" do
      bag = Xb5.Bag.new([1, 1, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 5, 5, 6, 7, 8, 9, 9, 9, 9, 9, 9])
      size = Xb5.Bag.size(bag)
      ref_elements = Xb5.Bag.to_list(bag)

      # Inclusive
      assert canon_equal?({:value, 1}, inclusive_percentile_rounded(0.00, bag))
      assert canon_equal?({:value, 1.1}, inclusive_percentile_rounded(0.05, bag))
      assert canon_equal?({:value, 2}, inclusive_percentile_rounded(0.10, bag))
      assert canon_equal?({:value, 2}, inclusive_percentile_rounded(0.15, bag))
      assert canon_equal?({:value, 2.4}, inclusive_percentile_rounded(0.20, bag))
      assert canon_equal?({:value, 3}, inclusive_percentile_rounded(0.25, bag))
      assert canon_equal?({:value, 3}, inclusive_percentile_rounded(0.30, bag))
      assert canon_equal?({:value, 3}, inclusive_percentile_rounded(0.35, bag))
      assert canon_equal?({:value, 3.8}, inclusive_percentile_rounded(0.40, bag))
      assert canon_equal?({:value, 4}, inclusive_percentile_rounded(0.45, bag))
      assert canon_equal?({:value, 4}, inclusive_percentile_rounded(0.50, bag))
      assert canon_equal?({:value, 5}, inclusive_percentile_rounded(0.55, bag))
      assert canon_equal?({:value, 5.2}, inclusive_percentile_rounded(0.60, bag))
      assert canon_equal?({:value, 6.3}, inclusive_percentile_rounded(0.65, bag))
      assert canon_equal?({:value, 7.4}, inclusive_percentile_rounded(0.70, bag))
      assert canon_equal?({:value, 8.5}, inclusive_percentile_rounded(0.75, bag))
      assert canon_equal?({:value, 9}, inclusive_percentile_rounded(0.80, bag))
      assert canon_equal?({:value, 9}, inclusive_percentile_rounded(0.85, bag))
      assert canon_equal?({:value, 9}, inclusive_percentile_rounded(0.90, bag))
      assert canon_equal?({:value, 9}, inclusive_percentile_rounded(0.95, bag))
      assert canon_equal?({:value, 9}, inclusive_percentile_rounded(1.00, bag))

      test_valid_percentile_inclusive(size, ref_elements, bag)

      # Exclusive
      assert canon_equal?(:none, exclusive_percentile_rounded(0.00, bag))
      assert canon_equal?({:value, 1}, exclusive_percentile_rounded(0.05, bag))
      assert canon_equal?({:value, 1.4}, exclusive_percentile_rounded(0.10, bag))
      assert canon_equal?({:value, 2}, exclusive_percentile_rounded(0.15, bag))
      assert canon_equal?({:value, 2}, exclusive_percentile_rounded(0.20, bag))
      assert canon_equal?({:value, 3}, exclusive_percentile_rounded(0.25, bag))
      assert canon_equal?({:value, 3}, exclusive_percentile_rounded(0.30, bag))
      assert canon_equal?({:value, 3}, exclusive_percentile_rounded(0.35, bag))
      assert canon_equal?({:value, 3.6}, exclusive_percentile_rounded(0.40, bag))
      assert canon_equal?({:value, 4}, exclusive_percentile_rounded(0.45, bag))
      assert canon_equal?({:value, 4}, exclusive_percentile_rounded(0.50, bag))
      assert canon_equal?({:value, 5}, exclusive_percentile_rounded(0.55, bag))
      assert canon_equal?({:value, 5.4}, exclusive_percentile_rounded(0.60, bag))
      assert canon_equal?({:value, 6.6}, exclusive_percentile_rounded(0.65, bag))
      assert canon_equal?({:value, 7.8}, exclusive_percentile_rounded(0.70, bag))
      assert canon_equal?({:value, 9}, exclusive_percentile_rounded(0.75, bag))
      assert canon_equal?({:value, 9}, exclusive_percentile_rounded(0.80, bag))
      assert canon_equal?({:value, 9}, exclusive_percentile_rounded(0.85, bag))
      assert canon_equal?({:value, 9}, exclusive_percentile_rounded(0.90, bag))
      assert canon_equal?({:value, 9}, exclusive_percentile_rounded(0.95, bag))
      assert canon_equal?(:none, exclusive_percentile_rounded(1.00, bag))

      test_valid_percentile_exclusive(size, ref_elements, bag)

      # Nearest rank
      assert canon_equal?(:none, Xb5.Bag.percentile(bag, 0.00, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 1}, Xb5.Bag.percentile(bag, 0.05, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 2}, Xb5.Bag.percentile(bag, 0.1, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 2}, Xb5.Bag.percentile(bag, 0.15, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 2}, Xb5.Bag.percentile(bag, 0.2, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 3}, Xb5.Bag.percentile(bag, 0.25, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 3}, Xb5.Bag.percentile(bag, 0.3, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 3}, Xb5.Bag.percentile(bag, 0.35, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 4}, Xb5.Bag.percentile(bag, 0.4, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 4}, Xb5.Bag.percentile(bag, 0.45, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 4}, Xb5.Bag.percentile(bag, 0.5, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 5}, Xb5.Bag.percentile(bag, 0.55, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 5}, Xb5.Bag.percentile(bag, 0.6, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 6}, Xb5.Bag.percentile(bag, 0.65, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 8}, Xb5.Bag.percentile(bag, 0.7, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 9}, Xb5.Bag.percentile(bag, 0.75, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 9}, Xb5.Bag.percentile(bag, 0.8, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 9}, Xb5.Bag.percentile(bag, 0.85, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 9}, Xb5.Bag.percentile(bag, 0.9, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 9}, Xb5.Bag.percentile(bag, 0.95, [{:method, :nearest_rank}]))
      assert canon_equal?({:value, 9}, Xb5.Bag.percentile(bag, 1, [{:method, :nearest_rank}]))

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
    test "round-trips through unwrap/wrap and rejects invalid inputs" do
      # Invalid inputs
      assert match?({:error, _}, :xb5_bag.unwrap(Xb5.Set.new() |> Xb5.Set.unwrap()))
      assert match?({:error, _}, :xb5_bag.unwrap(Xb5.Tree.new() |> Xb5.Tree.unwrap()))

      BTU.foreach_test_bag(fn _size, _ref_elements, bag ->
        unwrapped = Xb5.Bag.unwrap(bag)
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

  defp run_smaller(unique_ref, bag) do
    case unique_ref do
      [] ->
        elem = TU.new_element()
        assert Xb5.Bag.smaller(bag, elem) == :error

      [single] ->
        assert Xb5.Bag.smaller(bag, TU.randomly_switch_number_type(single)) == :error

        larger = TU.element_larger(single)
        assert Xb5.Bag.smaller(bag, larger) == {:ok, single}

        smaller = TU.element_smaller(single)
        assert Xb5.Bag.smaller(bag, smaller) == :error

      [first | next] ->
        assert Xb5.Bag.smaller(bag, TU.randomly_switch_number_type(first)) == :error

        smaller = TU.element_smaller(first)
        assert Xb5.Bag.smaller(bag, smaller) == :error

        run_smaller_recur(first, next, bag)
    end
  end

  defp run_smaller_recur(expected, [last], bag) do
    assert canon_equal?({:ok, expected}, Xb5.Bag.smaller(bag, TU.randomly_switch_number_type(last)))

    larger = TU.element_larger(last)
    assert larger > last
    assert Xb5.Bag.smaller(bag, larger) == {:ok, last}
  end

  defp run_smaller_recur(expected, [elem | next], bag) do
    assert Xb5.Bag.smaller(bag, TU.randomly_switch_number_type(elem)) == {:ok, expected}

    case TU.element_in_between(expected, elem) do
      {:found, in_between} ->
        assert in_between > expected
        assert in_between < elem
        assert Xb5.Bag.smaller(bag, in_between) == {:ok, expected}

      :none ->
        :ok
    end

    run_smaller_recur(elem, next, bag)
  end

  defp run_larger(unique_ref, bag) do
    case :lists.reverse(unique_ref) do
      [] ->
        elem = TU.new_element()
        assert Xb5.Bag.larger(bag, elem) == :error

      [single] ->
        assert Xb5.Bag.larger(bag, single) == :error

        larger = TU.element_larger(single)
        assert Xb5.Bag.larger(bag, larger) == :error

        smaller = TU.element_smaller(single)
        assert Xb5.Bag.larger(bag, smaller) == {:ok, single}

      [last | next] ->
        assert Xb5.Bag.larger(bag, TU.randomly_switch_number_type(last)) == :error

        larger = TU.element_larger(last)
        assert Xb5.Bag.larger(bag, larger) == :error

        run_larger_recur(last, next, bag)
    end
  end

  defp run_larger_recur(expected, [first], bag) do
    assert canon_equal?({:ok, expected}, Xb5.Bag.larger(bag, TU.randomly_switch_number_type(first)))

    smaller = TU.element_smaller(first)
    assert smaller < first
    assert Xb5.Bag.larger(bag, smaller) == {:ok, first}
  end

  defp run_larger_recur(expected, [elem | next], bag) do
    assert Xb5.Bag.larger(bag, TU.randomly_switch_number_type(elem)) == {:ok, expected}

    case TU.element_in_between(elem, expected) do
      {:found, in_between} ->
        assert in_between < expected
        assert in_between > elem
        assert Xb5.Bag.larger(bag, in_between) == {:ok, expected}

      :none ->
        :ok
    end

    run_larger_recur(elem, next, bag)
  end

  defp run_pop_smallest([expected | next], bag) do
    {taken, bag2} = Xb5.Bag.pop_smallest!(bag)
    assert taken == expected
    assert Xb5.Bag.size(bag2) == length(next)
    run_pop_smallest(next, bag2)
  end

  defp run_pop_smallest([], bag) do
    assert_raise ArgumentError, fn -> Xb5.Bag.pop_smallest!(bag) end
  end

  defp run_pop_largest([expected | next], bag) do
    {taken, bag2} = Xb5.Bag.pop_largest!(bag)
    assert taken == expected
    assert Xb5.Bag.size(bag2) == length(next)
    run_pop_largest(next, bag2)
  end

  defp run_pop_largest([], bag) do
    assert_raise ArgumentError, fn -> Xb5.Bag.pop_largest!(bag) end
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
        assert Xb5.Bag.percentile_bracket(bag, percentile) == :none
        assert Xb5.Bag.percentile(bag, percentile) == :none
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
          assert canon_equal?({:value, exact_elem}, Xb5.Bag.percentile(bag, percentile))
        else
          case Enum.slice(ref_elements, (low_rank - 1)..(high_rank - 1)) do
            [low_elem, high_elem | _] ->
              if low_elem == high_elem do
                assert canon_equal?(
                         {:exact, low_elem},
                         Xb5.Bag.percentile_bracket(bag, percentile)
                       )

                assert canon_equal?({:value, low_elem}, Xb5.Bag.percentile(bag, percentile))
              else
                low_perc = (low_rank - 1) / (size - 1)
                high_perc = (high_rank - 1) / (size - 1)
                perc_range = high_perc - low_perc
                high_weight = (percentile - low_perc) / perc_range
                low_weight = 1.0 - high_weight

                bracket = Xb5.Bag.percentile_bracket(bag, percentile)

                case bracket do
                  {:between, _low_b, _high_b} ->
                    assert true

                  {:exact, _} ->
                    assert true

                  other ->
                    flunk("Unexpected bracket: #{inspect(other)}")
                end

                if is_number(low_elem) and is_number(high_elem) do
                  result = Xb5.Bag.percentile(bag, percentile)

                  case result do
                    {:value, v} ->
                      expected = round_float_precision(low_weight * low_elem + high_weight * high_elem)
                      assert round_float_precision(v) == expected

                    other ->
                      flunk("Unexpected percentile result: #{inspect(other)}")
                  end
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
        assert Xb5.Bag.percentile_bracket(bag, percentile, [{:method, :exclusive}]) == :none
        assert Xb5.Bag.percentile(bag, percentile, [{:method, :exclusive}]) == :none
      end,
      size,
      :exclusive
    )
  end

  defp test_valid_percentile_exclusive(size, ref_elements, bag) do
    foreach_percentile(
      fn percentile, low_rank, high_rank ->
        if low_rank < 1 or high_rank > size do
          assert Xb5.Bag.percentile_bracket(bag, percentile, [{:method, :exclusive}]) == :none
          assert Xb5.Bag.percentile(bag, percentile, [{:method, :exclusive}]) == :none
        else
          if low_rank == high_rank do
            exact_elem = Enum.at(ref_elements, low_rank - 1)

            assert canon_equal?(
                     {:exact, exact_elem},
                     Xb5.Bag.percentile_bracket(bag, percentile, [{:method, :exclusive}])
                   )

            assert canon_equal?(
                     {:value, exact_elem},
                     Xb5.Bag.percentile(bag, percentile, [{:method, :exclusive}])
                   )
          else
            case Enum.slice(ref_elements, (low_rank - 1)..(high_rank - 1)) do
              [low_elem, high_elem | _] ->
                if low_elem == high_elem do
                  assert canon_equal?(
                           {:exact, low_elem},
                           Xb5.Bag.percentile_bracket(bag, percentile, [{:method, :exclusive}])
                         )

                  assert canon_equal?(
                           {:value, low_elem},
                           Xb5.Bag.percentile(bag, percentile, [{:method, :exclusive}])
                         )
                else
                  low_perc = low_rank / (size + 1)
                  high_perc = high_rank / (size + 1)
                  perc_range = high_perc - low_perc
                  high_weight = (percentile - low_perc) / perc_range
                  low_weight = 1.0 - high_weight

                  bracket =
                    Xb5.Bag.percentile_bracket(bag, percentile, [{:method, :exclusive}])

                  case bracket do
                    {:between, _low_b, _high_b} ->
                      assert true

                    {:exact, _} ->
                      assert true

                    other ->
                      flunk("Unexpected bracket: #{inspect(other)}")
                  end

                  if is_number(low_elem) and is_number(high_elem) do
                    result = Xb5.Bag.percentile(bag, percentile, [{:method, :exclusive}])

                    case result do
                      {:value, v} ->
                        expected =
                          round_float_precision(low_weight * low_elem + high_weight * high_elem)

                        assert round_float_precision(v) == expected

                      other ->
                        flunk("Unexpected percentile result: #{inspect(other)}")
                    end
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
        assert Xb5.Bag.percentile_bracket(bag, percentile, [{:method, :nearest_rank}]) == :none
        assert Xb5.Bag.percentile(bag, percentile, [{:method, :nearest_rank}]) == :none
      end,
      size,
      :nearest_rank
    )
  end

  defp test_valid_percentile_nearest_rank(size, ref_elements, bag) do
    foreach_percentile(
      fn percentile, _low_rank, exact_rank ->
        if exact_rank == 0 do
          assert Xb5.Bag.percentile_bracket(bag, percentile, [{:method, :nearest_rank}]) == :none
          assert Xb5.Bag.percentile(bag, percentile, [{:method, :nearest_rank}]) == :none
        else
          exact_elem = Enum.at(ref_elements, exact_rank - 1)

          assert canon_equal?(
                   {:exact, exact_elem},
                   Xb5.Bag.percentile_bracket(bag, percentile, [{:method, :nearest_rank}])
                 )

          assert canon_equal?(
                   {:value, exact_elem},
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
      {:value, value} when is_integer(value) ->
        {:value, value}

      {:value, value} when is_float(value) ->
        {:value, round_float_precision(value)}

      :none ->
        :none
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

  describe "fetch_index/get_index" do
    test "fetch_index returns ok-tuple or error" do
      bag = Xb5.Bag.new([1, 2, 3])
      assert Xb5.Bag.fetch_index(bag, 2) == {:ok, 1}
      assert Xb5.Bag.fetch_index(bag, 99) == :error
    end

    test "fetch_index! returns index or raises KeyError" do
      bag = Xb5.Bag.new([1, 2, 3])
      assert Xb5.Bag.fetch_index!(bag, 2) == 1
      assert_raise KeyError, fn -> Xb5.Bag.fetch_index!(bag, 99) end
    end

    test "get_index returns index or default" do
      bag = Xb5.Bag.new([1, 2, 3])
      assert Xb5.Bag.get_index(bag, 2) == 1
      assert Xb5.Bag.get_index(bag, 99) == nil
      assert Xb5.Bag.get_index(bag, 99, :missing) == :missing
    end
  end

  describe "new/2 with transform" do
    test "transforms elements before building bag" do
      bag = Xb5.Bag.new([3, 1, 2], fn x -> x * 10 end)
      assert Xb5.Bag.to_list(bag) == [10, 20, 30]
    end

    test "new/2 with Erlang bag term and transform" do
      base = Xb5.Bag.new([1, 2, 3])
      erlang_bag = :xb5_bag.wrap(Xb5.Bag.unwrap(base))
      bag = Xb5.Bag.new(erlang_bag, fn x -> x * 2 end)
      assert Xb5.Bag.to_list(bag) == [2, 4, 6]
    end
  end

  describe "reject" do
    test "keeps elements for which fun returns falsy" do
      bag = Xb5.Bag.new([1, 2, 3, 4])
      bag2 = Xb5.Bag.reject(bag, fn x -> x > 2 end)
      assert Xb5.Bag.to_list(bag2) == [1, 2]
    end
  end

  describe "Enumerable protocol" do
    test "Enum.count returns size" do
      bag = Xb5.Bag.new([1, 2, 2, 3])
      assert Enum.count(bag) == 4
    end

    test "Enum.member? checks membership" do
      bag = Xb5.Bag.new([1, 2, 2, 3])
      assert Enum.member?(bag, 2)
      refute Enum.member?(bag, 99)
    end

    test "Enum.to_list returns all elements sorted" do
      bag = Xb5.Bag.new([3, 1, 2, 1])
      assert Enum.to_list(bag) == [1, 1, 2, 3]
    end

    test "Enum.slice returns a range of elements" do
      bag = Xb5.Bag.new([1, 2, 3, 4, 5])
      assert Enum.slice(bag, 1, 3) == [2, 3, 4]
    end

    test "Enum.slice with step exercises step branches" do
      bag = Xb5.Bag.new([1, 2, 3, 4, 5, 6])
      # step 2: elements at positions 0, 2, 4
      assert Enum.slice(bag, 0..4//2) == [1, 3, 5]
    end
  end

  describe "Collectable protocol" do
    test "Enum.into inserts elements into existing bag" do
      base = Xb5.Bag.new([1])
      result = Enum.into([2, 3], base)
      assert Xb5.Bag.to_list(result) == [1, 2, 3]
    end

    test "for comprehension with into builds a bag" do
      result = for n <- [3, 1, 2], into: Xb5.Bag.new(), do: n
      assert Xb5.Bag.to_list(result) == [1, 2, 3]
    end

    test "halt branch via Stream.take_while" do
      # Stream.into + halt exercises the :halt branch
      result =
        [1, 2, 3, 4, 5]
        |> Stream.into(Xb5.Bag.new())
        |> Enum.take(2)

      assert result == [1, 2]
    end
  end

  describe "Inspect protocol" do
    test "inspect produces readable output" do
      bag = Xb5.Bag.new([1, 2])
      inspected = inspect(bag)
      assert String.starts_with?(inspected, "Xb5.Bag.new(")
    end
  end
end
