defmodule Xb5TreeTest do
  use ExUnit.Case, async: true
  @moduletag :tree

  alias Xb5TreeTestUtils, as: TTU
  alias Xb5TestUtils, as: TU

  doctest Xb5.Tree

  # ---------------------------------------------------------------------------
  # Basic API
  # ---------------------------------------------------------------------------

  describe "construction" do
    test "from enumerable matches key-wise insertion and size" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        assert TTU.canon_kvs(Xb5.Tree.to_list(tree)) == TTU.canon_kvs(ref_kvs)
        assert Xb5.Tree.size(tree) == size

        tree_from_inserts = TTU.new_tree_from_each_inserted(ref_kvs)
        assert TTU.canon_kvs(Xb5.Tree.to_list(tree_from_inserts)) == TTU.canon_kvs(ref_kvs)
      end)
    end
  end

  describe "construction_repeated" do
    test "repeated keys keep last occurrence, size unchanged" do
      TTU.foreach_tested_size(fn size, ref_kvs ->
        amount = min(length(ref_kvs), 50)

        keys_to_repeat =
          ref_kvs
          |> Enum.map(fn {k, _} -> k end)
          |> TU.list_shuffle()
          |> Enum.take(amount)

        Enum.each(keys_to_repeat, fn key_to_repeat ->
          switched_key = TU.randomly_switch_number_type(key_to_repeat)
          list = TTU.add_to_sorted_list(switched_key, :repeated, ref_kvs)

          tree = Xb5.Tree.new(list)

          assert Xb5.Tree.size(tree) == size

          assert TTU.canon_kvs(Xb5.Tree.to_list(tree)) ==
                   TTU.canon_kvs(sort_kv_list_keep_last_repeated(list))

          shuffled_list = TU.list_shuffle(list)
          tree_shuffled = Xb5.Tree.new(shuffled_list)

          assert Xb5.Tree.size(tree_shuffled) == size

          assert TTU.canon_kvs(Xb5.Tree.to_list(tree_shuffled)) ==
                   TTU.canon_kvs(sort_kv_list_keep_last_repeated(shuffled_list))
        end)
      end)
    end
  end

  describe "fetch/has_key?" do
    test "existing keys are found; absent keys return :error" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        foreach_existing_pair(
          fn key, value ->
            assert Xb5.Tree.has_key?(tree, key)
            assert Xb5.Tree.fetch!(tree, key) == value
            assert Xb5.Tree.fetch(tree, key) == {:ok, value}
          end,
          ref_kvs,
          size
        )

        foreach_non_existent_key(
          fn key ->
            refute Xb5.Tree.has_key?(tree, key)
            assert_raise KeyError, fn -> Xb5.Tree.fetch!(tree, key) end
            assert Xb5.Tree.fetch(tree, key) == :error
          end,
          ref_kvs,
          100
        )
      end)
    end
  end

  describe "put_new" do
    test "insert raises on existing key; insert on new key grows tree" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        foreach_existing_pair(
          fn key, _value ->
            tree2 = Xb5.Tree.put_new(tree, key, :new_value)
            assert Xb5.Tree.size(tree2) == size
            assert tree2 == tree
          end,
          ref_kvs,
          min(50, size)
        )

        foreach_non_existent_key(
          fn key ->
            value = {:new_value, make_ref()}
            tree2 = Xb5.Tree.put_new(tree, key, value)
            assert Xb5.Tree.size(tree2) == size + 1

            assert TTU.canon_kvs(Xb5.Tree.to_list(tree2)) ==
                     TTU.canon_kvs(TTU.add_to_sorted_list(key, value, ref_kvs))
          end,
          ref_kvs,
          50
        )
      end)
    end
  end

  describe "put (upsert)" do
    test "put on existing key replaces value, size unchanged; put on new key grows tree" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        foreach_existing_pair(
          fn key, _value ->
            new_value = {:new_value, make_ref()}
            tree2 = Xb5.Tree.put(tree, key, new_value)

            assert Xb5.Tree.size(tree2) == size

            assert TTU.canon_kvs(Xb5.Tree.to_list(tree2)) ==
                     TTU.canon_kvs(TTU.update_in_sorted_list(key, new_value, ref_kvs))
          end,
          ref_kvs,
          min(50, size)
        )

        foreach_non_existent_key(
          fn key ->
            value = {:new_value, make_ref()}
            tree2 = Xb5.Tree.put(tree, key, value)
            assert Xb5.Tree.size(tree2) == size + 1

            assert TTU.canon_kvs(Xb5.Tree.to_list(tree2)) ==
                     TTU.canon_kvs(TTU.add_to_sorted_list(key, value, ref_kvs))
          end,
          ref_kvs,
          50
        )
      end)
    end
  end

  describe "delete_sequential" do
    test "deletes keys one by one in order, interleaved with absent-key checks" do
      TTU.foreach_test_tree(fn _size, ref_kvs, tree ->
        delete_keys =
          ref_kvs
          |> Enum.map(fn {k, _} -> TU.randomly_switch_number_type(k) end)

        {tree_n, []} =
          Enum.reduce(delete_keys, {tree, ref_kvs}, fn key, {tree1, remaining1} ->
            check_delete_absent(tree1, remaining1, 3)

            tree2 = Xb5.Tree.delete(tree1, key)
            remaining2 = TTU.remove_from_sorted_list(key, remaining1)

            assert TTU.canon_kvs(Xb5.Tree.to_list(tree2)) == TTU.canon_kvs(remaining2)
            assert Xb5.Tree.size(tree2) == length(remaining2)

            {tree2, remaining2}
          end)

        assert Xb5.Tree.to_list(tree_n) == []
        assert Xb5.Tree.size(tree_n) == 0

        check_delete_absent(tree_n, [], 3)
      end)
    end
  end

  describe "delete_shuffled" do
    test "deletes keys in shuffled order, interleaved with absent-key checks" do
      TTU.foreach_test_tree(fn _size, ref_kvs, tree ->
        delete_keys =
          ref_kvs
          |> TU.list_shuffle()
          |> Enum.map(fn {k, _} -> TU.randomly_switch_number_type(k) end)

        {tree_n, []} =
          Enum.reduce(delete_keys, {tree, ref_kvs}, fn key, {tree1, remaining1} ->
            check_delete_absent(tree1, remaining1, 3)

            tree2 = Xb5.Tree.delete(tree1, key)
            remaining2 = TTU.remove_from_sorted_list(key, remaining1)

            assert TTU.canon_kvs(Xb5.Tree.to_list(tree2)) == TTU.canon_kvs(remaining2)
            assert Xb5.Tree.size(tree2) == length(remaining2)

            {tree2, remaining2}
          end)

        assert Xb5.Tree.to_list(tree_n) == []
        assert Xb5.Tree.size(tree_n) == 0

        check_delete_absent(tree_n, [], 3)
      end)
    end
  end

  describe "update" do
    test "update on existing key replaces value; update on absent key raises KeyError" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        foreach_existing_pair(
          fn key, _value ->
            new_value = {:new_value, make_ref()}
            tree2 = Xb5.Tree.replace!(tree, key, new_value)

            assert Xb5.Tree.size(tree2) == size

            assert TTU.canon_kvs(Xb5.Tree.to_list(tree2)) ==
                     TTU.canon_kvs(TTU.update_in_sorted_list(key, new_value, ref_kvs))
          end,
          ref_kvs,
          size
        )

        foreach_non_existent_key(
          fn key ->
            assert_raise KeyError, fn ->
              Xb5.Tree.replace!(tree, key, :new_value)
            end
          end,
          ref_kvs,
          50
        )
      end)
    end
  end

  describe "update! (lazy update)" do
    test "update! transforms existing value; raises KeyError on absent key" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        foreach_existing_pair(
          fn key, value ->
            new_value = make_ref()

            tree2 =
              Xb5.Tree.update!(tree, key, fn prev_value ->
                assert prev_value == value
                new_value
              end)

            assert Xb5.Tree.size(tree2) == size

            assert TTU.canon_kvs(Xb5.Tree.to_list(tree2)) ==
                     TTU.canon_kvs(TTU.update_in_sorted_list(key, new_value, ref_kvs))
          end,
          ref_kvs,
          size
        )

        foreach_non_existent_key(
          fn key ->
            assert_raise KeyError, fn -> Xb5.Tree.update!(tree, key, fn v -> v end) end
          end,
          ref_kvs,
          50
        )
      end)
    end
  end

  describe "update with default (lazy)" do
    test "updates existing key via fun; inserts with default for absent key" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        foreach_existing_pair(
          fn key, value ->
            new_value = make_ref()

            tree2 =
              Xb5.Tree.update(tree, key, :init_value, fn prev_value ->
                assert prev_value == value
                new_value
              end)

            assert Xb5.Tree.size(tree2) == size

            assert TTU.canon_kvs(Xb5.Tree.to_list(tree2)) ==
                     TTU.canon_kvs(TTU.update_in_sorted_list(key, new_value, ref_kvs))
          end,
          ref_kvs,
          size
        )

        foreach_non_existent_key(
          fn key ->
            init_value = make_ref()

            tree2 = Xb5.Tree.update(tree, key, init_value, fn _ -> raise "not to be called" end)

            assert Xb5.Tree.size(tree2) == size + 1

            assert TTU.canon_kvs(Xb5.Tree.to_list(tree2)) ==
                     TTU.canon_kvs(TTU.add_to_sorted_list(key, init_value, ref_kvs))
          end,
          ref_kvs,
          50
        )
      end)
    end
  end

  describe "keys" do
    test "returns all keys in sorted order" do
      TTU.foreach_test_tree(fn _size, ref_kvs, tree ->
        expected = Enum.map(ref_kvs, fn {k, _} -> TTU.canon_key(k) end)
        actual = Enum.map(Xb5.Tree.keys(tree), &TTU.canon_key/1)
        assert actual == expected
      end)
    end
  end

  describe "values" do
    test "returns all values in key-sorted order" do
      TTU.foreach_test_tree(fn _size, ref_kvs, tree ->
        expected = Enum.map(ref_kvs, fn {_, v} -> v end)
        assert Xb5.Tree.values(tree) == expected
      end)
    end
  end

  describe "take_sequential (pop!)" do
    test "takes keys one by one in order, interleaved with absent-key checks" do
      TTU.foreach_test_tree(fn _size, ref_kvs, tree ->
        take_pairs =
          Enum.map(ref_kvs, fn {k, v} -> {TU.randomly_switch_number_type(k), v} end)

        {tree_n, []} =
          Enum.reduce(take_pairs, {tree, ref_kvs}, fn {key, value}, {tree1, remaining1} ->
            check_take_absent(tree1, remaining1, 3)

            {taken_value, tree2} = Xb5.Tree.pop!(tree1, key)
            assert taken_value == value

            remaining2 = TTU.remove_from_sorted_list(key, remaining1)
            assert TTU.canon_kvs(Xb5.Tree.to_list(tree2)) == TTU.canon_kvs(remaining2)
            assert Xb5.Tree.size(tree2) == length(remaining2)

            {tree2, remaining2}
          end)

        assert Xb5.Tree.to_list(tree_n) == []
        assert Xb5.Tree.size(tree_n) == 0

        check_take_absent(tree_n, [], 3)
      end)
    end
  end

  describe "take_shuffled (pop!)" do
    test "takes keys in shuffled order, interleaved with absent-key checks" do
      TTU.foreach_test_tree(fn _size, ref_kvs, tree ->
        take_pairs =
          ref_kvs
          |> TU.list_shuffle()
          |> Enum.map(fn {k, v} -> {TU.randomly_switch_number_type(k), v} end)

        {tree_n, []} =
          Enum.reduce(take_pairs, {tree, ref_kvs}, fn {key, value}, {tree1, remaining1} ->
            check_take_absent(tree1, remaining1, 3)

            {taken_value, tree2} = Xb5.Tree.pop!(tree1, key)
            assert taken_value == value

            remaining2 = TTU.remove_from_sorted_list(key, remaining1)
            assert TTU.canon_kvs(Xb5.Tree.to_list(tree2)) == TTU.canon_kvs(remaining2)
            assert Xb5.Tree.size(tree2) == length(remaining2)

            {tree2, remaining2}
          end)

        assert Xb5.Tree.to_list(tree_n) == []
        assert Xb5.Tree.size(tree_n) == 0

        check_take_absent(tree_n, [], 3)
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # first/last/lower/higher
  # ---------------------------------------------------------------------------

  describe "first" do
    test "returns nil default on empty tree, returns first entry otherwise" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        if size == 0 do
          assert Xb5.Tree.first(tree) == nil
          assert Xb5.Tree.first(tree, :empty) == :empty
        else
          {expected_key, expected_value} = hd(ref_kvs)
          {actual_key, actual_value} = Xb5.Tree.first(tree)
          assert TTU.canon_key(actual_key) == TTU.canon_key(expected_key)
          assert actual_value == expected_value
          assert Xb5.Tree.first(tree, :empty) == Xb5.Tree.first(tree)
        end
      end)
    end
  end

  describe "first!" do
    test "raises on empty tree, returns first entry otherwise" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        if size == 0 do
          assert_raise Xb5.EmptyError, fn -> Xb5.Tree.first!(tree) end
        else
          {expected_key, expected_value} = hd(ref_kvs)
          {actual_key, actual_value} = Xb5.Tree.first!(tree)
          assert TTU.canon_key(actual_key) == TTU.canon_key(expected_key)
          assert actual_value == expected_value
        end
      end)
    end
  end

  describe "last" do
    test "returns nil default on empty tree, returns last entry otherwise" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        if size == 0 do
          assert Xb5.Tree.last(tree) == nil
          assert Xb5.Tree.last(tree, :empty) == :empty
        else
          {expected_key, expected_value} = List.last(ref_kvs)
          {actual_key, actual_value} = Xb5.Tree.last(tree)
          assert TTU.canon_key(actual_key) == TTU.canon_key(expected_key)
          assert actual_value == expected_value
          assert Xb5.Tree.last(tree, :empty) == Xb5.Tree.last(tree)
        end
      end)
    end
  end

  describe "last!" do
    test "raises on empty tree, returns last entry otherwise" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        if size == 0 do
          assert_raise Xb5.EmptyError, fn -> Xb5.Tree.last!(tree) end
        else
          {expected_key, expected_value} = List.last(ref_kvs)
          {actual_key, actual_value} = Xb5.Tree.last!(tree)
          assert TTU.canon_key(actual_key) == TTU.canon_key(expected_key)
          assert actual_value == expected_value
        end
      end)
    end
  end

  describe "lower" do
    test "returns the largest pair with key strictly less than given" do
      TTU.foreach_test_tree(fn _size, ref_kvs, tree ->
        run_lower(ref_kvs, tree)
      end)
    end
  end

  describe "higher" do
    test "returns the smallest pair with key strictly greater than given" do
      TTU.foreach_test_tree(fn _size, ref_kvs, tree ->
        run_higher(ref_kvs, tree)
      end)
    end
  end

  describe "pop_first!" do
    test "repeatedly removes and returns the first pair" do
      TTU.foreach_test_tree(fn _size, ref_kvs, tree ->
        run_pop_first(ref_kvs, tree)
      end)
    end
  end

  describe "pop_last!" do
    test "repeatedly removes and returns the last pair" do
      TTU.foreach_test_tree(fn _size, ref_kvs, tree ->
        run_pop_last(Enum.reverse(ref_kvs), tree)
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Additional functions
  # ---------------------------------------------------------------------------

  describe "map" do
    test "applies fun to all values, size unchanged" do
      TTU.foreach_test_tree(fn _size, ref_kvs, tree ->
        run_map(ref_kvs, tree)
      end)
    end
  end

  describe "rewrap" do
    test "round-trips through Erlang xb5_trees wrap/unwrap!" do
      TTU.foreach_test_tree(fn _size, _ref_kvs, tree ->
        unwrapped = Xb5.Tree.unwrap!(tree)
        erlang_term = :xb5_trees.wrap(unwrapped)
        rewrapped = Xb5.Tree.new(erlang_term)
        assert rewrapped == tree
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Additional API coverage
  # ---------------------------------------------------------------------------

  describe "get/get_lazy/get_and_update/get_and_update!" do
    test "get returns value or default" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        foreach_existing_pair(
          fn key, value ->
            assert Xb5.Tree.get(tree, key) == value
          end,
          ref_kvs,
          min(5, size)
        )

        foreach_non_existent_key(
          fn key ->
            assert Xb5.Tree.get(tree, key) == nil
            assert Xb5.Tree.get(tree, key, :sentinel) == :sentinel
          end,
          ref_kvs,
          3
        )
      end)
    end

    test "get_lazy returns value without calling fun; calls fun when absent" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        foreach_existing_pair(
          fn key, value ->
            assert Xb5.Tree.get_lazy(tree, key, fn -> raise "should not be called" end) == value
          end,
          ref_kvs,
          min(5, size)
        )

        foreach_non_existent_key(
          fn key ->
            sentinel = make_ref()
            assert Xb5.Tree.get_lazy(tree, key, fn -> sentinel end) == sentinel
          end,
          ref_kvs,
          3
        )
      end)
    end

    test "get_and_update updates or pops existing; inserts or no-ops when absent" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        foreach_existing_pair(
          fn key, value ->
            new_value = make_ref()
            {old, tree2} = Xb5.Tree.get_and_update(tree, key, fn v -> {v, new_value} end)
            assert old == value
            assert Xb5.Tree.fetch!(tree2, key) == new_value
            assert Xb5.Tree.size(tree2) == size

            {old2, tree3} = Xb5.Tree.get_and_update(tree, key, fn _ -> :pop end)
            assert old2 == value
            refute Xb5.Tree.has_key?(tree3, key)
            assert Xb5.Tree.size(tree3) == size - 1
          end,
          ref_kvs,
          min(5, size)
        )

        foreach_non_existent_key(
          fn key ->
            sentinel = make_ref()
            {old, tree2} = Xb5.Tree.get_and_update(tree, key, fn nil -> {nil, sentinel} end)
            assert old == nil
            assert Xb5.Tree.fetch!(tree2, key) == sentinel
            assert Xb5.Tree.size(tree2) == size + 1

            {nil_v, tree3} = Xb5.Tree.get_and_update(tree, key, fn _ -> :pop end)
            assert nil_v == nil
            assert tree3 == tree
          end,
          ref_kvs,
          3
        )
      end)
    end

    test "get_and_update! updates or pops existing; raises on missing key" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        foreach_existing_pair(
          fn key, value ->
            new_value = make_ref()
            {old, tree2} = Xb5.Tree.get_and_update!(tree, key, fn v -> {v, new_value} end)
            assert old == value
            assert Xb5.Tree.fetch!(tree2, key) == new_value
            assert Xb5.Tree.size(tree2) == size

            {old2, tree3} = Xb5.Tree.get_and_update!(tree, key, fn _ -> :pop end)
            assert old2 == value
            refute Xb5.Tree.has_key?(tree3, key)
          end,
          ref_kvs,
          min(5, size)
        )

        foreach_non_existent_key(
          fn key ->
            assert_raise KeyError, fn ->
              Xb5.Tree.get_and_update!(tree, key, fn _ -> {:x, :y} end)
            end
          end,
          ref_kvs,
          3
        )
      end)
    end
  end

  describe "drop/equal?" do
    test "drop removes multiple keys" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        drop_count = min(max(1, div(size, 5)), length(ref_kvs))

        keys_to_drop =
          ref_kvs |> TU.list_shuffle() |> Enum.take(drop_count) |> Enum.map(fn {k, _} -> k end)

        tree2 = Xb5.Tree.drop(tree, keys_to_drop)
        dropped_set = MapSet.new(keys_to_drop, &TTU.canon_key/1)

        expected =
          Enum.reject(ref_kvs, fn {k, _} -> MapSet.member?(dropped_set, TTU.canon_key(k)) end)

        assert Xb5.Tree.size(tree2) == length(expected)
        assert TTU.canon_kvs(Xb5.Tree.to_list(tree2)) == TTU.canon_kvs(expected)
      end)
    end

    test "equal? returns true for identical content, false otherwise" do
      TTU.foreach_test_tree(fn _size, ref_kvs, tree ->
        tree2 = Xb5.Tree.new(ref_kvs)
        assert Xb5.Tree.equal?(tree, tree2)

        empty = Xb5.Tree.new()

        if ref_kvs == [] do
          assert Xb5.Tree.equal?(tree, empty)
        else
          refute Xb5.Tree.equal?(tree, empty)
        end
      end)
    end
  end

  describe "filter/reject/from_keys/take" do
    test "filter keeps matching pairs" do
      TTU.foreach_test_tree(fn _size, ref_kvs, tree ->
        pred = fn {k, _v} -> rem(:erlang.phash2(TTU.canon_key(k)), 2) == 0 end
        tree2 = Xb5.Tree.filter(tree, pred)
        expected = Enum.filter(ref_kvs, pred)
        assert Xb5.Tree.size(tree2) == length(expected)
        assert TTU.canon_kvs(Xb5.Tree.to_list(tree2)) == TTU.canon_kvs(expected)
      end)
    end

    test "reject removes matching pairs" do
      TTU.foreach_test_tree(fn _size, ref_kvs, tree ->
        pred = fn {k, _v} -> rem(:erlang.phash2(TTU.canon_key(k)), 2) == 0 end
        tree2 = Xb5.Tree.reject(tree, pred)
        expected = Enum.reject(ref_kvs, pred)
        assert Xb5.Tree.size(tree2) == length(expected)
        assert TTU.canon_kvs(Xb5.Tree.to_list(tree2)) == TTU.canon_kvs(expected)
      end)
    end

    test "from_keys builds tree mapping each key to the given value" do
      TTU.foreach_test_tree(fn _size, ref_kvs, _tree ->
        keys = Enum.map(ref_kvs, fn {k, _} -> k end)
        sentinel = make_ref()
        tree2 = Xb5.Tree.from_keys(keys, sentinel)
        assert Xb5.Tree.size(tree2) == length(keys)
        assert Enum.all?(Xb5.Tree.to_list(tree2), fn {_k, v} -> v === sentinel end)

        assert TTU.canon_kvs(Enum.map(Xb5.Tree.to_list(tree2), fn {k, _} -> {k, :x} end)) ==
                 TTU.canon_kvs(Enum.map(ref_kvs, fn {k, _} -> {k, :x} end))
      end)
    end

    test "take keeps only the given keys" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        take_count = min(max(1, div(size, 3)), length(ref_kvs))

        keys_to_take =
          ref_kvs |> TU.list_shuffle() |> Enum.take(take_count) |> Enum.map(fn {k, _} -> k end)

        tree2 = Xb5.Tree.take(tree, keys_to_take)
        taken_set = MapSet.new(keys_to_take, &TTU.canon_key/1)

        expected =
          Enum.filter(ref_kvs, fn {k, _} -> MapSet.member?(taken_set, TTU.canon_key(k)) end)

        assert Xb5.Tree.size(tree2) == length(expected)
        assert TTU.canon_kvs(Xb5.Tree.to_list(tree2)) == TTU.canon_kvs(expected)
      end)
    end
  end

  describe "replace/replace!/replace_lazy" do
    test "replace updates existing key, no-op on missing" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        foreach_existing_pair(
          fn key, _value ->
            new_value = make_ref()
            tree2 = Xb5.Tree.replace(tree, key, new_value)
            assert Xb5.Tree.size(tree2) == size

            assert TTU.canon_kvs(Xb5.Tree.to_list(tree2)) ==
                     TTU.canon_kvs(TTU.update_in_sorted_list(key, new_value, ref_kvs))
          end,
          ref_kvs,
          min(5, size)
        )

        foreach_non_existent_key(
          fn key ->
            assert Xb5.Tree.replace(tree, key, :new_value) == tree
          end,
          ref_kvs,
          3
        )
      end)
    end

    test "replace! updates existing, raises on missing" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        foreach_existing_pair(
          fn key, _value ->
            new_value = make_ref()
            tree2 = Xb5.Tree.replace!(tree, key, new_value)
            assert Xb5.Tree.size(tree2) == size

            assert TTU.canon_kvs(Xb5.Tree.to_list(tree2)) ==
                     TTU.canon_kvs(TTU.update_in_sorted_list(key, new_value, ref_kvs))
          end,
          ref_kvs,
          min(5, size)
        )

        foreach_non_existent_key(
          fn key ->
            assert_raise KeyError, fn -> Xb5.Tree.replace!(tree, key, :new_value) end
          end,
          ref_kvs,
          3
        )
      end)
    end

    test "replace_lazy updates existing via fun, no-op on missing" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        foreach_existing_pair(
          fn key, value ->
            new_value = make_ref()

            tree2 =
              Xb5.Tree.replace_lazy(tree, key, fn prev ->
                assert prev == value
                new_value
              end)

            assert Xb5.Tree.size(tree2) == size

            assert TTU.canon_kvs(Xb5.Tree.to_list(tree2)) ==
                     TTU.canon_kvs(TTU.update_in_sorted_list(key, new_value, ref_kvs))
          end,
          ref_kvs,
          min(5, size)
        )

        foreach_non_existent_key(
          fn key ->
            assert Xb5.Tree.replace_lazy(tree, key, fn _ -> raise "should not be called" end) ==
                     tree
          end,
          ref_kvs,
          3
        )
      end)
    end
  end

  describe "merge (2-arg and 3-arg)" do
    test "merge/2 right-hand wins, both argument orderings verified" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        TTU.foreach_second_tree(
          fn ref_kvs2, tree2 ->
            merged_ab = Xb5.Tree.merge(tree, tree2)
            expected_ab = merge_lists(fn _k, _v1, v2 -> v2 end, ref_kvs, ref_kvs2)
            assert Xb5.Tree.size(merged_ab) == length(expected_ab)
            assert TTU.canon_kvs(Xb5.Tree.to_list(merged_ab)) == TTU.canon_kvs(expected_ab)

            merged_ba = Xb5.Tree.merge(tree2, tree)
            expected_ba = merge_lists(fn _k, _v1, v2 -> v2 end, ref_kvs2, ref_kvs)
            assert Xb5.Tree.size(merged_ba) == length(expected_ba)
            assert TTU.canon_kvs(Xb5.Tree.to_list(merged_ba)) == TTU.canon_kvs(expected_ba)
          end,
          size,
          ref_kvs
        )
      end)
    end

    test "merge/3 fun resolves conflicts, both argument orderings verified" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        TTU.foreach_second_tree(
          fn ref_kvs2, tree2 ->
            merge_fun = fn _k, v1, v2 -> {v1, v2} end

            merged_ab = Xb5.Tree.merge(tree, tree2, merge_fun)
            expected_ab = merge_lists(merge_fun, ref_kvs, ref_kvs2)
            assert Xb5.Tree.size(merged_ab) == length(expected_ab)
            assert TTU.canon_kvs(Xb5.Tree.to_list(merged_ab)) == TTU.canon_kvs(expected_ab)

            merged_ba = Xb5.Tree.merge(tree2, tree, merge_fun)
            expected_ba = merge_lists(merge_fun, ref_kvs2, ref_kvs)
            assert Xb5.Tree.size(merged_ba) == length(expected_ba)
            assert TTU.canon_kvs(Xb5.Tree.to_list(merged_ba)) == TTU.canon_kvs(expected_ba)
          end,
          size,
          ref_kvs
        )
      end)
    end

    test "merge/2 with sequential boundary trees (variants2)" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        TTU.foreach_second_tree(
          fn ref_kvs2, tree2 ->
            merged_ab = Xb5.Tree.merge(tree, tree2)
            expected_ab = merge_lists(fn _k, _v1, v2 -> v2 end, ref_kvs, ref_kvs2)
            assert Xb5.Tree.size(merged_ab) == length(expected_ab)
            assert TTU.canon_kvs(Xb5.Tree.to_list(merged_ab)) == TTU.canon_kvs(expected_ab)
          end,
          size,
          ref_kvs,
          test_variants2: true
        )
      end)
    end
  end

  describe "intersect" do
    test "intersect/2 keeps common keys with right-hand values, both orderings verified" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        TTU.foreach_second_tree(
          fn ref_kvs2, tree2 ->
            canon1_map = Map.new(TTU.canon_kvs(ref_kvs))
            canon2_map = Map.new(TTU.canon_kvs(ref_kvs2))
            common_keys = for {k, _} <- canon1_map, Map.has_key?(canon2_map, k), do: k

            result_ab = Xb5.Tree.intersect(tree, tree2)
            result_ab_map = Map.new(TTU.canon_kvs(Xb5.Tree.to_list(result_ab)))
            assert Xb5.Tree.size(result_ab) == length(common_keys)
            Enum.each(common_keys, fn k -> assert result_ab_map[k] == canon2_map[k] end)

            result_ba = Xb5.Tree.intersect(tree2, tree)
            result_ba_map = Map.new(TTU.canon_kvs(Xb5.Tree.to_list(result_ba)))
            assert Xb5.Tree.size(result_ba) == length(common_keys)
            Enum.each(common_keys, fn k -> assert result_ba_map[k] == canon1_map[k] end)
          end,
          size,
          ref_kvs
        )
      end)
    end

    test "intersect/3 fun merges conflicting values, both orderings verified" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        TTU.foreach_second_tree(
          fn ref_kvs2, tree2 ->
            canon1_map = Map.new(TTU.canon_kvs(ref_kvs))
            canon2_map = Map.new(TTU.canon_kvs(ref_kvs2))
            common_keys = for {k, _} <- canon1_map, Map.has_key?(canon2_map, k), do: k
            intersect_fun = fn _k, v1, v2 -> {v1, v2} end

            result_ab = Xb5.Tree.intersect(tree, tree2, intersect_fun)
            result_ab_map = Map.new(TTU.canon_kvs(Xb5.Tree.to_list(result_ab)))
            assert Xb5.Tree.size(result_ab) == length(common_keys)

            Enum.each(common_keys, fn k ->
              assert result_ab_map[k] == intersect_fun.(k, canon1_map[k], canon2_map[k])
            end)

            result_ba = Xb5.Tree.intersect(tree2, tree, intersect_fun)
            result_ba_map = Map.new(TTU.canon_kvs(Xb5.Tree.to_list(result_ba)))
            assert Xb5.Tree.size(result_ba) == length(common_keys)

            Enum.each(common_keys, fn k ->
              assert result_ba_map[k] == intersect_fun.(k, canon2_map[k], canon1_map[k])
            end)
          end,
          size,
          ref_kvs
        )
      end)
    end
  end

  describe "split/split_with" do
    @tag :tree_split
    test "split partitions by key list" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        split_count = min(max(1, div(size, 3)), length(ref_kvs))

        keys_to_split =
          (ref_kvs |> TU.list_shuffle() |> Enum.take(split_count) |> Enum.map(fn {k, _} -> k end)) ++
            for _ <- 1..15, do: TU.new_element()

        {t_in, t_out} = Xb5.Tree.split(tree, keys_to_split)
        split_set = MapSet.new(keys_to_split, &TTU.canon_key/1)

        expected_in =
          Enum.filter(ref_kvs, fn {k, _} -> MapSet.member?(split_set, TTU.canon_key(k)) end)

        expected_out =
          Enum.reject(ref_kvs, fn {k, _} -> MapSet.member?(split_set, TTU.canon_key(k)) end)

        assert Xb5.Tree.size(t_in) == length(expected_in)
        assert TTU.canon_kvs(Xb5.Tree.to_list(t_in)) == TTU.canon_kvs(expected_in)
        assert Xb5.Tree.size(t_out) == length(expected_out)
        assert TTU.canon_kvs(Xb5.Tree.to_list(t_out)) == TTU.canon_kvs(expected_out)
      end)
    end

    test "split_with partitions by predicate" do
      TTU.foreach_test_tree(fn _size, ref_kvs, tree ->
        pred = fn {k, _v} -> rem(:erlang.phash2(TTU.canon_key(k)), 2) == 0 end
        {t_true, t_false} = Xb5.Tree.split_with(tree, pred)
        expected_true = Enum.filter(ref_kvs, pred)
        expected_false = Enum.reject(ref_kvs, pred)

        assert Xb5.Tree.size(t_true) == length(expected_true)
        assert TTU.canon_kvs(Xb5.Tree.to_list(t_true)) == TTU.canon_kvs(expected_true)
        assert Xb5.Tree.size(t_false) == length(expected_false)
        assert TTU.canon_kvs(Xb5.Tree.to_list(t_false)) == TTU.canon_kvs(expected_false)
      end)
    end
  end

  describe "put_new_lazy" do
    test "inserts via fun when key absent; fun not called when key present" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        foreach_non_existent_key(
          fn key ->
            sentinel = make_ref()
            tree2 = Xb5.Tree.put_new_lazy(tree, key, fn -> sentinel end)
            assert Xb5.Tree.fetch!(tree2, key) == sentinel
            assert Xb5.Tree.size(tree2) == size + 1
          end,
          ref_kvs,
          3
        )

        foreach_existing_pair(
          fn key, _value ->
            tree2 = Xb5.Tree.put_new_lazy(tree, key, fn -> raise "should not be called" end)
            assert tree2 == tree
          end,
          ref_kvs,
          min(5, size)
        )
      end)
    end
  end

  describe "pop/pop_lazy" do
    test "pop returns {value, tree_without_key}; default when absent" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        foreach_existing_pair(
          fn key, value ->
            {val, tree2} = Xb5.Tree.pop(tree, key)
            assert val == value
            refute Xb5.Tree.has_key?(tree2, key)
            assert Xb5.Tree.size(tree2) == size - 1
          end,
          ref_kvs,
          min(5, size)
        )

        foreach_non_existent_key(
          fn key ->
            {val, tree2} = Xb5.Tree.pop(tree, key)
            assert val == nil
            assert tree2 == tree
            {val3, _} = Xb5.Tree.pop(tree, key, :sentinel)
            assert val3 == :sentinel
          end,
          ref_kvs,
          3
        )
      end)
    end

    test "pop_lazy returns value when present; calls fun when absent" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        foreach_existing_pair(
          fn key, value ->
            {val, tree2} = Xb5.Tree.pop_lazy(tree, key, fn -> raise "should not be called" end)
            assert val == value
            refute Xb5.Tree.has_key?(tree2, key)
            assert Xb5.Tree.size(tree2) == size - 1
          end,
          ref_kvs,
          min(5, size)
        )

        foreach_non_existent_key(
          fn key ->
            sentinel = make_ref()
            {val, tree2} = Xb5.Tree.pop_lazy(tree, key, fn -> sentinel end)
            assert val == sentinel
            assert tree2 == tree
          end,
          ref_kvs,
          3
        )
      end)
    end
  end

  describe "new/2 with transform" do
    test "transforms pairs before building tree" do
      TTU.foreach_test_tree(fn _size, ref_kvs, _tree ->
        transform = fn {k, v} -> {k, {v, :transformed}} end
        tree2 = Xb5.Tree.new(ref_kvs, transform)
        expected = Enum.map(ref_kvs, transform)
        assert Xb5.Tree.size(tree2) == length(expected)
        assert TTU.canon_kvs(Xb5.Tree.to_list(tree2)) == TTU.canon_kvs(expected)
      end)
    end

    test "new/2 with Erlang term and transform" do
      base = Xb5.Tree.new([{1, :a}, {2, :b}])
      erlang_term = :xb5_trees.wrap(Xb5.Tree.unwrap!(base))
      tree = Xb5.Tree.new(erlang_term, fn {k, v} -> {k, {v, k}} end)
      assert Xb5.Tree.to_list(tree) == [{1, {:a, 1}}, {2, {:b, 2}}]
    end
  end

  # ---------------------------------------------------------------------------
  # Stream API
  # ---------------------------------------------------------------------------

  describe "stream" do
    test "asc matches to_list" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        result = Xb5.Tree.stream(tree) |> Enum.to_list()
        assert TTU.canon_kvs(result) == TTU.canon_kvs(ref_kvs)
        assert length(result) == size
      end)
    end

    test "desc matches desc to_list" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        result = Xb5.Tree.stream(tree, :desc) |> Enum.to_list()
        assert TTU.canon_kvs(result) == TTU.canon_kvs(Enum.reverse(ref_kvs))
        assert length(result) == size
      end)
    end

    test "partial consumption via Enum.take" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        if size >= 2 do
          take = div(size, 2)
          result = Xb5.Tree.stream(tree) |> Enum.take(take)
          assert TTU.canon_kvs(result) == TTU.canon_kvs(Enum.take(ref_kvs, take))
        end
      end)
    end
  end

  describe "stream_from" do
    test "asc: multiple sampled existing keys as start points" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        if size > 0 do
          ref_kvs
          |> TU.list_shuffle()
          |> Enum.take(10)
          |> Enum.each(fn {start_key, _} ->
            result = Xb5.Tree.stream_from(tree, start_key) |> Enum.to_list()
            expected = Enum.drop_while(ref_kvs, fn {k, _} -> k < start_key end)
            assert TTU.canon_kvs(result) == TTU.canon_kvs(expected)
          end)
        end
      end)
    end

    test "asc: starting below all keys yields full stream" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        if size > 0 do
          {first_key, _} = hd(ref_kvs)
          before_all = TU.element_smaller(first_key)
          result = Xb5.Tree.stream_from(tree, before_all) |> Enum.to_list()
          assert TTU.canon_kvs(result) == TTU.canon_kvs(ref_kvs)
        end
      end)
    end

    test "asc: starting above all keys yields empty stream" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        if size > 0 do
          {last_key, _} = List.last(ref_kvs)
          after_all = TU.element_larger(last_key)
          assert Xb5.Tree.stream_from(tree, after_all) |> Enum.to_list() == []
        end
      end)
    end

    test "desc: multiple sampled existing keys as start points" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        if size > 0 do
          ref_kvs
          |> TU.list_shuffle()
          |> Enum.take(10)
          |> Enum.each(fn {start_key, _} ->
            result = Xb5.Tree.stream_from(tree, start_key, :desc) |> Enum.to_list()

            expected =
              ref_kvs |> Enum.take_while(fn {k, _} -> k <= start_key end) |> Enum.reverse()

            assert TTU.canon_kvs(result) == TTU.canon_kvs(expected)
          end)
        end
      end)
    end

    test "desc: starting above all keys yields full desc stream" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        if size > 0 do
          {last_key, _} = List.last(ref_kvs)
          after_all = TU.element_larger(last_key)
          result = Xb5.Tree.stream_from(tree, after_all, :desc) |> Enum.to_list()
          assert TTU.canon_kvs(result) == TTU.canon_kvs(Enum.reverse(ref_kvs))
        end
      end)
    end

    test "desc: starting below all keys yields empty stream" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        if size > 0 do
          {first_key, _} = hd(ref_kvs)
          before_all = TU.element_smaller(first_key)
          assert Xb5.Tree.stream_from(tree, before_all, :desc) |> Enum.to_list() == []
        end
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Protocol coverage
  # ---------------------------------------------------------------------------

  describe "Enumerable protocol" do
    test "count, member?, reduce, and slice" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        assert Enum.count(tree) == size

        ref_kvs
        |> TU.list_shuffle()
        |> Enum.take(min(5, size))
        |> Enum.each(fn {k, v} ->
          assert Enum.member?(tree, {TU.randomly_switch_number_type(k), v})
          refute Enum.member?(tree, {k, make_ref()})

          switched_v = TU.randomly_switch_number_type(v)

          if switched_v == v do
            assert Enum.member?(tree, {k, switched_v})
          else
            refute Enum.member?(tree, {k, switched_v})
          end
        end)

        foreach_non_existent_key(
          fn key ->
            refute Enum.member?(tree, {key, :anything})
          end,
          ref_kvs,
          3
        )

        refute Enum.member?(tree, :not_a_pair)
        assert TTU.canon_kvs(Enum.to_list(tree)) == TTU.canon_kvs(ref_kvs)

        if size >= 2 do
          slice_start = div(size, 4)
          slice_len = max(1, div(size, 2))
          sliced = Enum.slice(tree, slice_start, slice_len)
          expected_slice = Enum.slice(ref_kvs, slice_start, slice_len)
          assert TTU.canon_kvs(sliced) == TTU.canon_kvs(expected_slice)
        end
      end)
    end

    test "Enum.slice with step and non-zero start" do
      tree = Xb5.Tree.new([{1, :a}, {2, :b}, {3, :c}, {4, :d}])
      # step 2 with non-zero start: entries at positions 1, 3
      assert Enum.slice(tree, 1..3//2) == [{2, :b}, {4, :d}]
      tree2 = Xb5.Tree.new([{1, :a}, {2, :b}, {3, :c}, {4, :d}, {5, :e}, {6, :f}])
      # step 2 from start: entries at positions 0, 2, 4
      assert Enum.slice(tree2, 0..4//2) == [{1, :a}, {3, :c}, {5, :e}]
    end
  end

  describe "Collectable protocol" do
    test "Enum.into builds tree from pairs" do
      TTU.foreach_test_tree(fn _size, ref_kvs, _tree ->
        result = Enum.into(ref_kvs, Xb5.Tree.new())
        assert TTU.canon_kvs(Xb5.Tree.to_list(result)) == TTU.canon_kvs(ref_kvs)
      end)
    end

    test "for comprehension with into builds a tree" do
      TTU.foreach_test_tree(fn _size, ref_kvs, _tree ->
        result = for {k, v} <- ref_kvs, into: Xb5.Tree.new(), do: {k, v}
        assert TTU.canon_kvs(Xb5.Tree.to_list(result)) == TTU.canon_kvs(ref_kvs)
      end)
    end

    test "halt branch via Stream.into" do
      result =
        [{1, :a}, {2, :b}, {3, :c}, {4, :d}]
        |> Stream.into(Xb5.Tree.new())
        |> Enum.take(2)

      assert result == [{1, :a}, {2, :b}]
    end
  end

  describe "Inspect protocol" do
    test "inspect produces readable output for all tree sizes" do
      TTU.foreach_test_tree(fn _size, _ref_kvs, tree ->
        inspected = inspect(tree)
        assert String.starts_with?(inspected, "Xb5.Tree.new(")
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Generates `amount` non-existent keys and calls fun.(key) on each.
  defp foreach_non_existent_key(_fun, _ref_kvs, 0), do: :ok

  defp foreach_non_existent_key(fun, ref_kvs, amount) do
    key = TU.new_element()

    if Enum.any?(ref_kvs, fn {k, _} -> k == key end) do
      foreach_non_existent_key(fun, ref_kvs, amount)
    else
      fun.(key)
      foreach_non_existent_key(fun, ref_kvs, amount - 1)
    end
  end

  # Picks up to `amount` existing pairs (shuffled), switches key type, calls fun.
  defp foreach_existing_pair(fun, ref_kvs, amount) do
    ref_kvs
    |> TU.list_shuffle()
    |> Enum.take(amount)
    |> Enum.each(fn {key, value} ->
      fun.(TU.randomly_switch_number_type(key), value)
    end)
  end

  # Checks that deleting `amount` absent keys is a no-op.
  defp check_delete_absent(_tree, _remaining, 0), do: :ok

  defp check_delete_absent(tree, remaining, amount) do
    key = TU.new_element()

    if Enum.any?(remaining, fn {k, _} -> k == key end) do
      check_delete_absent(tree, remaining, amount)
    else
      # Xb5.Tree.delete is idempotent; absent key returns tree unchanged.
      assert Xb5.Tree.delete(tree, key) == tree
      check_delete_absent(tree, remaining, amount - 1)
    end
  end

  # Checks that popping `amount` absent keys returns :error.
  defp check_take_absent(_tree, _remaining, 0), do: :ok

  defp check_take_absent(tree, remaining, amount) do
    key = TU.new_element()

    if Enum.any?(remaining, fn {k, _} -> k == key end) do
      check_take_absent(tree, remaining, amount)
    else
      assert_raise KeyError, fn -> Xb5.Tree.pop!(tree, key) end
      assert Xb5.Tree.pop(tree, key) == {nil, tree}
      check_take_absent(tree, remaining, amount - 1)
    end
  end

  # Keeps last occurrence of duplicate keys (mirrors from_list/1 internals, no circular dep).
  defp sort_kv_list_keep_last_repeated(list) do
    :lists.ukeysort(1, :lists.reverse(list))
  end

  # ---------------------------------------------------------------------------
  # lower / higher helpers
  # ---------------------------------------------------------------------------

  defp run_lower(ref_kvs, tree) do
    case ref_kvs do
      [] ->
        key = TU.new_element()
        assert Xb5.Tree.lower(tree, key) == :error

      [{single_key, single_value}] ->
        assert Xb5.Tree.lower(tree, TU.randomly_switch_number_type(single_key)) == :error

        larger_key = TU.element_larger(single_key)
        {ak, av} = Xb5.Tree.lower(tree, larger_key)
        assert TTU.canon_key(ak) == TTU.canon_key(single_key)
        assert av == single_value

        smaller_key = TU.element_smaller(single_key)
        assert Xb5.Tree.lower(tree, smaller_key) == :error

      [{first_key, first_value} | next] ->
        assert Xb5.Tree.lower(tree, TU.randomly_switch_number_type(first_key)) == :error

        smaller_key = TU.element_smaller(first_key)
        assert Xb5.Tree.lower(tree, smaller_key) == :error

        run_lower_recur(first_key, first_value, next, tree)
    end
  end

  defp run_lower_recur(expected_key, expected_value, [{last_key, last_value}], tree) do
    result = Xb5.Tree.lower(tree, TU.randomly_switch_number_type(last_key))
    assert result != :error
    {rk, rv} = result
    assert TTU.canon_key(rk) == TTU.canon_key(expected_key)
    assert rv == expected_value

    larger_key = TU.element_larger(last_key)
    assert larger_key > last_key
    result2 = Xb5.Tree.lower(tree, larger_key)
    assert result2 != :error
    {rk2, rv2} = result2
    assert TTU.canon_key(rk2) == TTU.canon_key(last_key)
    assert rv2 == last_value
  end

  defp run_lower_recur(expected_key, expected_value, [{key, value} | next], tree) do
    result = Xb5.Tree.lower(tree, TU.randomly_switch_number_type(key))
    assert result != :error
    {rk, rv} = result
    assert TTU.canon_key(rk) == TTU.canon_key(expected_key)
    assert rv == expected_value

    case TU.element_in_between(expected_key, key) do
      {:found, in_between} ->
        assert in_between > expected_key
        assert in_between < key
        result2 = Xb5.Tree.lower(tree, in_between)
        assert result2 != :error
        {rk2, rv2} = result2
        assert TTU.canon_key(rk2) == TTU.canon_key(expected_key)
        assert rv2 == expected_value

      :none ->
        :ok
    end

    run_lower_recur(key, value, next, tree)
  end

  # ---------------------------------------------------------------------------

  defp run_higher(ref_kvs, tree) do
    case Enum.reverse(ref_kvs) do
      [] ->
        key = TU.new_element()
        assert Xb5.Tree.higher(tree, key) == :error

      [{single_key, single_value}] ->
        assert Xb5.Tree.higher(tree, TU.randomly_switch_number_type(single_key)) == :error

        larger_key = TU.element_larger(single_key)
        assert Xb5.Tree.higher(tree, larger_key) == :error

        smaller_key = TU.element_smaller(single_key)
        result = Xb5.Tree.higher(tree, smaller_key)
        assert result != :error
        {rk, rv} = result
        assert TTU.canon_key(rk) == TTU.canon_key(single_key)
        assert rv == single_value

      [{last_key, last_value} | next] ->
        assert Xb5.Tree.higher(tree, TU.randomly_switch_number_type(last_key)) == :error

        larger_key = TU.element_larger(last_key)
        assert Xb5.Tree.higher(tree, larger_key) == :error

        run_higher_recur(last_key, last_value, next, tree)
    end
  end

  defp run_higher_recur(expected_key, expected_value, [{first_key, first_value}], tree) do
    result = Xb5.Tree.higher(tree, TU.randomly_switch_number_type(first_key))
    assert result != :error
    {rk, rv} = result
    assert TTU.canon_key(rk) == TTU.canon_key(expected_key)
    assert rv == expected_value

    smaller_key = TU.element_smaller(first_key)
    assert smaller_key < first_key
    result2 = Xb5.Tree.higher(tree, smaller_key)
    assert result2 != :error
    {rk2, rv2} = result2
    assert TTU.canon_key(rk2) == TTU.canon_key(first_key)
    assert rv2 == first_value
  end

  defp run_higher_recur(expected_key, expected_value, [{key, value} | next], tree) do
    result = Xb5.Tree.higher(tree, TU.randomly_switch_number_type(key))
    assert result != :error
    {rk, rv} = result
    assert TTU.canon_key(rk) == TTU.canon_key(expected_key)
    assert rv == expected_value

    case TU.element_in_between(key, expected_key) do
      {:found, in_between} ->
        assert in_between < expected_key
        assert in_between > key
        result2 = Xb5.Tree.higher(tree, in_between)
        assert result2 != :error
        {rk2, rv2} = result2
        assert TTU.canon_key(rk2) == TTU.canon_key(expected_key)
        assert rv2 == expected_value

      :none ->
        :ok
    end

    run_higher_recur(key, value, next, tree)
  end

  # ---------------------------------------------------------------------------

  defp run_pop_first([{expected_key, expected_value} | next], tree) do
    {taken_key, taken_value, tree2} = Xb5.Tree.pop_first!(tree)
    assert TTU.canon_key(taken_key) == TTU.canon_key(expected_key)
    assert taken_value == expected_value
    assert Xb5.Tree.size(tree2) == length(next)
    run_pop_first(next, tree2)
  end

  defp run_pop_first([], tree) do
    assert_raise Xb5.EmptyError, fn -> Xb5.Tree.pop_first!(tree) end
  end

  defp run_pop_last([{expected_key, expected_value} | next], tree) do
    {taken_key, taken_value, tree2} = Xb5.Tree.pop_last!(tree)
    assert TTU.canon_key(taken_key) == TTU.canon_key(expected_key)
    assert taken_value == expected_value
    assert Xb5.Tree.size(tree2) == length(next)
    run_pop_last(next, tree2)
  end

  defp run_pop_last([], tree) do
    assert_raise Xb5.EmptyError, fn -> Xb5.Tree.pop_last!(tree) end
  end

  # ---------------------------------------------------------------------------
  # merge_lists helper
  # ---------------------------------------------------------------------------

  defp merge_lists(fun, [{k1, v1} = pair1 | next1] = l1, [{k2, v2} = pair2 | next2] = l2) do
    cond do
      k1 < k2 -> [pair1 | merge_lists(fun, next1, l2)]
      k2 < k1 -> [pair2 | merge_lists(fun, l1, next2)]
      true -> [{k1, fun.(k1, v1, v2)} | merge_lists(fun, next1, next2)]
    end
  end

  defp merge_lists(_fun, [], l2), do: l2
  defp merge_lists(_fun, l1, []), do: l1

  # ---------------------------------------------------------------------------
  # map helper
  # ---------------------------------------------------------------------------

  defp run_map(ref_kvs, tree) do
    percentages_mapped = [0.0, 0.2, 0.5, 0.7, 1.0]

    Enum.each(percentages_mapped, fn pct ->
      p_hash_range = 100_000
      p_hash_ceiling = round(pct * p_hash_range)
      random_factor = :rand.uniform()

      map_fun = fn k, v ->
        canon_k = TTU.canon_key(k)

        # credo:disable-for-next-line Credo.Check.Refactor.Nesting
        if :erlang.phash2(canon_k, p_hash_range) < p_hash_ceiling do
          :erlang.phash2([random_factor | canon_k], 3)
        else
          v
        end
      end

      mapped_tree = Xb5.Tree.map(tree, map_fun)

      expected_mapped =
        Enum.map(ref_kvs, fn {k, v} -> {k, map_fun.(k, v)} end)

      assert Xb5.Tree.size(mapped_tree) == length(expected_mapped)

      assert TTU.canon_kvs(Xb5.Tree.to_list(mapped_tree)) ==
               TTU.canon_kvs(expected_mapped)
    end)
  end
end
