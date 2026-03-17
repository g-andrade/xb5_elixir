defmodule Xb5TreeTest do
  use ExUnit.Case, async: true
  alias Xb5TreeTestUtils, as: TTU
  alias Xb5TestUtils, as: TU

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
  # Smaller and Larger
  # ---------------------------------------------------------------------------

  describe "smallest!/largest!" do
    test "smallest! returns the pair with the smallest key; raises on empty" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        if size == 0 do
          assert_raise ArgumentError, fn -> Xb5.Tree.smallest!(tree) end
        else
          {expected_key, expected_value} = hd(ref_kvs)
          {actual_key, actual_value} = Xb5.Tree.smallest!(tree)
          assert TTU.canon_key(actual_key) == TTU.canon_key(expected_key)
          assert actual_value == expected_value
        end
      end)
    end

    test "largest! returns the pair with the largest key; raises on empty" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        if size == 0 do
          assert_raise ArgumentError, fn -> Xb5.Tree.largest!(tree) end
        else
          {expected_key, expected_value} = List.last(ref_kvs)
          {actual_key, actual_value} = Xb5.Tree.largest!(tree)
          assert TTU.canon_key(actual_key) == TTU.canon_key(expected_key)
          assert actual_value == expected_value
        end
      end)
    end
  end

  describe "smaller" do
    test "returns the largest pair with key strictly less than given" do
      TTU.foreach_test_tree(fn _size, ref_kvs, tree ->
        run_smaller(ref_kvs, tree)
      end)
    end
  end

  describe "larger" do
    test "returns the smallest pair with key strictly greater than given" do
      TTU.foreach_test_tree(fn _size, ref_kvs, tree ->
        run_larger(ref_kvs, tree)
      end)
    end
  end

  describe "pop_smallest!" do
    test "repeatedly removes and returns the smallest pair" do
      TTU.foreach_test_tree(fn _size, ref_kvs, tree ->
        run_pop_smallest(ref_kvs, tree)
      end)
    end
  end

  describe "pop_largest!" do
    test "repeatedly removes and returns the largest pair" do
      TTU.foreach_test_tree(fn _size, ref_kvs, tree ->
        run_pop_largest(Enum.reverse(ref_kvs), tree)
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
    test "round-trips through Erlang xb5_trees wrap/unwrap" do
      TTU.foreach_test_tree(fn _size, _ref_kvs, tree ->
        unwrapped = Xb5.Tree.unwrap(tree)
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
      tree = Xb5.Tree.new([{:a, 1}, {:b, 2}])
      assert Xb5.Tree.get(tree, :a) == 1
      assert Xb5.Tree.get(tree, :c) == nil
      assert Xb5.Tree.get(tree, :c, :default) == :default
    end

    test "get_lazy returns value or calls fun" do
      tree = Xb5.Tree.new([{:a, 1}])
      assert Xb5.Tree.get_lazy(tree, :a, fn -> :default end) == 1
      assert Xb5.Tree.get_lazy(tree, :b, fn -> :default end) == :default
    end

    test "get_and_update updates or inserts, supports :pop" do
      tree = Xb5.Tree.new([{:a, 1}, {:b, 2}])
      # update existing
      {old, tree2} = Xb5.Tree.get_and_update(tree, :a, fn v -> {v, v + 10} end)
      assert old == 1
      assert Xb5.Tree.fetch!(tree2, :a) == 11
      # pop existing (`:pop` sentinel removes the key)
      {old2, tree3} = Xb5.Tree.get_and_update(tree, :a, fn v -> {v, :pop} end)
      assert old2 == 1
      # value is set to :pop, not deleted (Map.get_and_update semantics: :pop in tuple sets the value)
      assert Xb5.Tree.fetch!(tree3, :a) == :pop
      # actual pop (return bare :pop atom)
      {old3, tree4} = Xb5.Tree.get_and_update(tree, :a, fn _ -> :pop end)
      assert old3 == 1
      refute Xb5.Tree.has_key?(tree4, :a)
      # insert absent (nil)
      {_old4, tree5} = Xb5.Tree.get_and_update(tree, :c, fn nil -> {nil, 99} end)
      assert Xb5.Tree.fetch!(tree5, :c) == 99
      # pop absent (no-op)
      {nil_v, tree6} = Xb5.Tree.get_and_update(tree, :d, fn _ -> :pop end)
      assert nil_v == nil
      assert tree6 == tree
    end

    test "get_and_update! updates or pops, raises on missing key" do
      tree = Xb5.Tree.new([{:a, 1}])
      {old, tree2} = Xb5.Tree.get_and_update!(tree, :a, fn v -> {v, v + 10} end)
      assert old == 1
      assert Xb5.Tree.fetch!(tree2, :a) == 11
      {old2, tree3} = Xb5.Tree.get_and_update!(tree, :a, fn _ -> :pop end)
      assert old2 == 1
      refute Xb5.Tree.has_key?(tree3, :a)
      assert_raise KeyError, fn -> Xb5.Tree.get_and_update!(tree, :missing, fn _ -> {:x, :y} end) end
    end
  end

  describe "drop/equal?" do
    test "drop removes multiple keys" do
      tree = Xb5.Tree.new([{:a, 1}, {:b, 2}, {:c, 3}])
      tree2 = Xb5.Tree.drop(tree, [:a, :c])
      assert Xb5.Tree.to_list(tree2) == [{:b, 2}]
    end

    test "equal? compares two trees" do
      t1 = Xb5.Tree.new([{:a, 1}, {:b, 2}])
      t2 = Xb5.Tree.new([{:a, 1}, {:b, 2}])
      t3 = Xb5.Tree.new([{:a, 1}])
      assert Xb5.Tree.equal?(t1, t2)
      refute Xb5.Tree.equal?(t1, t3)
    end
  end

  describe "filter/reject/from_keys/take" do
    test "filter keeps matching pairs" do
      tree = Xb5.Tree.new([{:a, 1}, {:b, 2}, {:c, 3}])
      tree2 = Xb5.Tree.filter(tree, fn {_k, v} -> v > 1 end)
      assert Xb5.Tree.to_list(tree2) == [{:b, 2}, {:c, 3}]
    end

    test "reject removes matching pairs" do
      tree = Xb5.Tree.new([{:a, 1}, {:b, 2}, {:c, 3}])
      tree2 = Xb5.Tree.reject(tree, fn {_k, v} -> v > 1 end)
      assert Xb5.Tree.to_list(tree2) == [{:a, 1}]
    end

    test "from_keys builds tree with shared value" do
      tree = Xb5.Tree.from_keys([:a, :b, :c], 0)
      assert Xb5.Tree.to_list(tree) == [{:a, 0}, {:b, 0}, {:c, 0}]
    end

    test "take keeps only the given keys" do
      tree = Xb5.Tree.new([{:a, 1}, {:b, 2}, {:c, 3}])
      tree2 = Xb5.Tree.take(tree, [:a, :c])
      assert Xb5.Tree.to_list(tree2) == [{:a, 1}, {:c, 3}]
    end
  end

  describe "replace/replace!/replace_lazy" do
    test "replace updates existing key, no-op on missing" do
      tree = Xb5.Tree.new([{:a, 1}])
      tree2 = Xb5.Tree.replace(tree, :a, 99)
      assert Xb5.Tree.fetch!(tree2, :a) == 99
      tree3 = Xb5.Tree.replace(tree, :missing, 99)
      assert tree3 == tree
    end

    test "replace! updates existing, raises on missing" do
      tree = Xb5.Tree.new([{:a, 1}])
      tree2 = Xb5.Tree.replace!(tree, :a, 99)
      assert Xb5.Tree.fetch!(tree2, :a) == 99
      assert_raise KeyError, fn -> Xb5.Tree.replace!(tree, :missing, 99) end
    end

    test "replace_lazy updates existing via fun, no-op on missing" do
      tree = Xb5.Tree.new([{:a, 1}])
      tree2 = Xb5.Tree.replace_lazy(tree, :a, fn v -> v + 10 end)
      assert Xb5.Tree.fetch!(tree2, :a) == 11
      tree3 = Xb5.Tree.replace_lazy(tree, :missing, fn _ -> 99 end)
      assert tree3 == tree
    end
  end

  describe "merge (2-arg and 3-arg)" do
    test "merge/2 merges trees, right-hand wins on conflict" do
      t1 = Xb5.Tree.new([{:a, 1}, {:b, 2}])
      t2 = Xb5.Tree.new([{:b, 20}, {:c, 3}])
      merged = Xb5.Tree.merge(t1, t2)
      assert Xb5.Tree.to_list(merged) == [{:a, 1}, {:b, 20}, {:c, 3}]
    end

    test "merge/3 uses fun for conflicts" do
      t1 = Xb5.Tree.new([{:a, 1}, {:b, 2}])
      t2 = Xb5.Tree.new([{:b, 20}, {:c, 3}])
      merged = Xb5.Tree.merge(t1, t2, fn _k, v1, v2 -> v1 + v2 end)
      assert Xb5.Tree.to_list(merged) == [{:a, 1}, {:b, 22}, {:c, 3}]
    end

    test "merge with second tree (randomized)" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        TTU.foreach_second_tree(
          fn ref_kvs2, tree2 ->
            # right-hand wins: merge tree1, tree2 — tree2 values win
            merged = Xb5.Tree.merge(tree, tree2)
            expected = merge_lists(fn _k, _v1, v2 -> v2 end, ref_kvs, ref_kvs2)
            assert Xb5.Tree.size(merged) == length(expected)
            assert TTU.canon_kvs(Xb5.Tree.to_list(merged)) == TTU.canon_kvs(expected)
          end,
          size,
          ref_kvs
        )
      end)
    end
  end

  describe "intersect" do
    test "intersect/2 keeps common keys with right-hand values" do
      t1 = Xb5.Tree.new([{:a, 1}, {:b, 2}])
      t2 = Xb5.Tree.new([{:b, 20}, {:c, 3}])
      result = Xb5.Tree.intersect(t1, t2)
      assert Xb5.Tree.to_list(result) == [{:b, 20}]
    end

    test "intersect/3 uses fun to merge conflicting values" do
      t1 = Xb5.Tree.new([{:a, 1}, {:b, 2}])
      t2 = Xb5.Tree.new([{:b, 20}, {:c, 3}])
      result = Xb5.Tree.intersect(t1, t2, fn _k, v1, v2 -> v1 + v2 end)
      assert Xb5.Tree.to_list(result) == [{:b, 22}]
    end
  end

  describe "split/split_with" do
    test "split partitions by key list" do
      tree = Xb5.Tree.new([{:a, 1}, {:b, 2}, {:c, 3}, {:d, 4}])
      {t1, t2} = Xb5.Tree.split(tree, [:b, :d])
      assert Xb5.Tree.to_list(t1) == [{:b, 2}, {:d, 4}]
      assert Xb5.Tree.to_list(t2) == [{:a, 1}, {:c, 3}]
    end

    test "split_with partitions by predicate" do
      tree = Xb5.Tree.new([{:a, 1}, {:b, 2}, {:c, 3}])
      {t1, t2} = Xb5.Tree.split_with(tree, fn {_k, v} -> v > 1 end)
      assert Xb5.Tree.to_list(t1) == [{:b, 2}, {:c, 3}]
      assert Xb5.Tree.to_list(t2) == [{:a, 1}]
    end
  end

  describe "put_new_lazy" do
    test "inserts via fun when key absent; no-op when present" do
      tree = Xb5.Tree.new([{:a, 1}])
      tree2 = Xb5.Tree.put_new_lazy(tree, :b, fn -> 99 end)
      assert Xb5.Tree.fetch!(tree2, :b) == 99
      tree3 = Xb5.Tree.put_new_lazy(tree, :a, fn -> raise "should not be called" end)
      assert tree3 == tree
    end
  end

  describe "pop/pop_lazy" do
    test "pop returns value + updated tree; default when absent" do
      tree = Xb5.Tree.new([{:a, 1}, {:b, 2}])
      {val, tree2} = Xb5.Tree.pop(tree, :a)
      assert val == 1
      refute Xb5.Tree.has_key?(tree2, :a)
      {val2, tree3} = Xb5.Tree.pop(tree, :missing)
      assert val2 == nil
      assert tree3 == tree
      {val3, _} = Xb5.Tree.pop(tree, :missing, :def)
      assert val3 == :def
    end

    test "pop_lazy returns value + tree; calls fun when absent" do
      tree = Xb5.Tree.new([{:a, 1}])
      {val, tree2} = Xb5.Tree.pop_lazy(tree, :a, fn -> :default end)
      assert val == 1
      refute Xb5.Tree.has_key?(tree2, :a)
      {val2, tree3} = Xb5.Tree.pop_lazy(tree, :missing, fn -> :default end)
      assert val2 == :default
      assert tree3 == tree
    end
  end

  describe "new/2 with transform" do
    test "transforms pairs before building tree" do
      tree = Xb5.Tree.new([{:a, 1}, {:b, 2}], fn {k, v} -> {k, v * 10} end)
      assert Xb5.Tree.to_list(tree) == [{:a, 10}, {:b, 20}]
    end

    test "new/2 with Erlang term and transform" do
      base = Xb5.Tree.new([{1, :a}, {2, :b}])
      erlang_term = :xb5_trees.wrap(Xb5.Tree.unwrap(base))
      tree = Xb5.Tree.new(erlang_term, fn {k, v} -> {k, {v, k}} end)
      assert Xb5.Tree.to_list(tree) == [{1, {:a, 1}}, {2, {:b, 2}}]
    end
  end

  # ---------------------------------------------------------------------------
  # Protocol coverage
  # ---------------------------------------------------------------------------

  describe "merge via foreach_second_tree with variants2" do
    test "merge/2 with sequential boundary trees" do
      TTU.foreach_test_tree(fn size, ref_kvs, tree ->
        TTU.foreach_second_tree(
          fn ref_kvs2, tree2 ->
            merged = Xb5.Tree.merge(tree, tree2)
            expected = merge_lists(fn _k, _v1, v2 -> v2 end, ref_kvs, ref_kvs2)
            assert Xb5.Tree.size(merged) == length(expected)
          end,
          size,
          ref_kvs,
          test_variants2: true
        )
      end)
    end
  end

  describe "Enumerable protocol" do
    test "Enum.count returns size" do
      tree = Xb5.Tree.new([{:a, 1}, {:b, 2}, {:c, 3}])
      assert Enum.count(tree) == 3
    end

    test "Enum.member? checks key-value pair membership" do
      tree = Xb5.Tree.new([{:a, 1}, {:b, 2}])
      assert Enum.member?(tree, {:a, 1})
      refute Enum.member?(tree, {:a, 99})
      refute Enum.member?(tree, {:missing, 1})
      # non-tuple value should be false
      refute Enum.member?(tree, :not_a_pair)
    end

    test "Enum.to_list returns key-value pairs" do
      tree = Xb5.Tree.new([{:a, 1}, {:b, 2}])
      assert Enum.to_list(tree) == [{:a, 1}, {:b, 2}]
    end

    test "Enum.slice works correctly" do
      tree = Xb5.Tree.new([{:a, 1}, {:b, 2}, {:c, 3}, {:d, 4}])
      assert Enum.slice(tree, 1, 2) == [{:b, 2}, {:c, 3}]
    end
  end

  describe "Collectable protocol" do
    test "Enum.into inserts pairs into an existing tree" do
      base = Xb5.Tree.new([{:a, 1}])
      result = Enum.into([{:b, 2}, {:c, 3}], base)
      assert Xb5.Tree.to_list(result) == [{:a, 1}, {:b, 2}, {:c, 3}]
    end

    test "for comprehension with into builds a tree" do
      result = for n <- 1..3, into: Xb5.Tree.new(), do: {n, n * n}
      assert Xb5.Tree.to_list(result) == [{1, 1}, {2, 4}, {3, 9}]
    end

    test "halt branch via Stream.take_while" do
      result =
        [{1, :a}, {2, :b}, {3, :c}, {4, :d}]
        |> Stream.into(Xb5.Tree.new())
        |> Enum.take(2)

      assert result == [{1, :a}, {2, :b}]
    end
  end

  describe "Inspect protocol" do
    test "inspect produces readable output" do
      tree = Xb5.Tree.new([{:a, 1}])
      inspected = inspect(tree)
      assert String.starts_with?(inspected, "Xb5.Tree.new(")
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

  # Keeps last repeated key, using == equality (mirrors Erlang's gb_trees:enter behavior).
  defp sort_kv_list_keep_last_repeated(list) do
    # Build a tree by calling put/3 on each pair (last one wins for == keys).
    tree = Enum.reduce(list, Xb5.Tree.new(), fn {k, v}, acc -> Xb5.Tree.put(acc, k, v) end)
    Xb5.Tree.to_list(tree)
  end

  # ---------------------------------------------------------------------------
  # smaller / larger helpers
  # ---------------------------------------------------------------------------

  defp run_smaller(ref_kvs, tree) do
    case ref_kvs do
      [] ->
        key = TU.new_element()
        assert Xb5.Tree.smaller(tree, key) == :error

      [{single_key, single_value}] ->
        assert Xb5.Tree.smaller(tree, TU.randomly_switch_number_type(single_key)) == :error

        larger_key = TU.element_larger(single_key)
        {ak, av} = Xb5.Tree.smaller(tree, larger_key)
        assert TTU.canon_key(ak) == TTU.canon_key(single_key)
        assert av == single_value

        smaller_key = TU.element_smaller(single_key)
        assert Xb5.Tree.smaller(tree, smaller_key) == :error

      [{first_key, first_value} | next] ->
        assert Xb5.Tree.smaller(tree, TU.randomly_switch_number_type(first_key)) == :error

        smaller_key = TU.element_smaller(first_key)
        assert Xb5.Tree.smaller(tree, smaller_key) == :error

        run_smaller_recur(first_key, first_value, next, tree)
    end
  end

  defp run_smaller_recur(expected_key, expected_value, [{last_key, last_value}], tree) do
    result = Xb5.Tree.smaller(tree, TU.randomly_switch_number_type(last_key))
    assert result != :error
    {rk, rv} = result
    assert TTU.canon_key(rk) == TTU.canon_key(expected_key)
    assert rv == expected_value

    larger_key = TU.element_larger(last_key)
    assert larger_key > last_key
    result2 = Xb5.Tree.smaller(tree, larger_key)
    assert result2 != :error
    {rk2, rv2} = result2
    assert TTU.canon_key(rk2) == TTU.canon_key(last_key)
    assert rv2 == last_value
  end

  defp run_smaller_recur(expected_key, expected_value, [{key, value} | next], tree) do
    result = Xb5.Tree.smaller(tree, TU.randomly_switch_number_type(key))
    assert result != :error
    {rk, rv} = result
    assert TTU.canon_key(rk) == TTU.canon_key(expected_key)
    assert rv == expected_value

    case TU.element_in_between(expected_key, key) do
      {:found, in_between} ->
        assert in_between > expected_key
        assert in_between < key
        result2 = Xb5.Tree.smaller(tree, in_between)
        assert result2 != :error
        {rk2, rv2} = result2
        assert TTU.canon_key(rk2) == TTU.canon_key(expected_key)
        assert rv2 == expected_value

      :none ->
        :ok
    end

    run_smaller_recur(key, value, next, tree)
  end

  # ---------------------------------------------------------------------------

  defp run_larger(ref_kvs, tree) do
    case Enum.reverse(ref_kvs) do
      [] ->
        key = TU.new_element()
        assert Xb5.Tree.larger(tree, key) == :error

      [{single_key, single_value}] ->
        assert Xb5.Tree.larger(tree, TU.randomly_switch_number_type(single_key)) == :error

        larger_key = TU.element_larger(single_key)
        assert Xb5.Tree.larger(tree, larger_key) == :error

        smaller_key = TU.element_smaller(single_key)
        result = Xb5.Tree.larger(tree, smaller_key)
        assert result != :error
        {rk, rv} = result
        assert TTU.canon_key(rk) == TTU.canon_key(single_key)
        assert rv == single_value

      [{last_key, last_value} | next] ->
        assert Xb5.Tree.larger(tree, TU.randomly_switch_number_type(last_key)) == :error

        larger_key = TU.element_larger(last_key)
        assert Xb5.Tree.larger(tree, larger_key) == :error

        run_larger_recur(last_key, last_value, next, tree)
    end
  end

  defp run_larger_recur(expected_key, expected_value, [{first_key, first_value}], tree) do
    result = Xb5.Tree.larger(tree, TU.randomly_switch_number_type(first_key))
    assert result != :error
    {rk, rv} = result
    assert TTU.canon_key(rk) == TTU.canon_key(expected_key)
    assert rv == expected_value

    smaller_key = TU.element_smaller(first_key)
    assert smaller_key < first_key
    result2 = Xb5.Tree.larger(tree, smaller_key)
    assert result2 != :error
    {rk2, rv2} = result2
    assert TTU.canon_key(rk2) == TTU.canon_key(first_key)
    assert rv2 == first_value
  end

  defp run_larger_recur(expected_key, expected_value, [{key, value} | next], tree) do
    result = Xb5.Tree.larger(tree, TU.randomly_switch_number_type(key))
    assert result != :error
    {rk, rv} = result
    assert TTU.canon_key(rk) == TTU.canon_key(expected_key)
    assert rv == expected_value

    case TU.element_in_between(key, expected_key) do
      {:found, in_between} ->
        assert in_between < expected_key
        assert in_between > key
        result2 = Xb5.Tree.larger(tree, in_between)
        assert result2 != :error
        {rk2, rv2} = result2
        assert TTU.canon_key(rk2) == TTU.canon_key(expected_key)
        assert rv2 == expected_value

      :none ->
        :ok
    end

    run_larger_recur(key, value, next, tree)
  end

  # ---------------------------------------------------------------------------

  defp run_pop_smallest([{expected_key, expected_value} | next], tree) do
    {taken_key, taken_value, tree2} = Xb5.Tree.pop_smallest!(tree)
    assert TTU.canon_key(taken_key) == TTU.canon_key(expected_key)
    assert taken_value == expected_value
    assert Xb5.Tree.size(tree2) == length(next)
    run_pop_smallest(next, tree2)
  end

  defp run_pop_smallest([], tree) do
    assert_raise ArgumentError, fn -> Xb5.Tree.pop_smallest!(tree) end
  end

  defp run_pop_largest([{expected_key, expected_value} | next], tree) do
    {taken_key, taken_value, tree2} = Xb5.Tree.pop_largest!(tree)
    assert TTU.canon_key(taken_key) == TTU.canon_key(expected_key)
    assert taken_value == expected_value
    assert Xb5.Tree.size(tree2) == length(next)
    run_pop_largest(next, tree2)
  end

  defp run_pop_largest([], tree) do
    assert_raise ArgumentError, fn -> Xb5.Tree.pop_largest!(tree) end
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
