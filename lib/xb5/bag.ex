defmodule Xb5.Bag do
  @moduledoc """
  An ordered multiset (bag) backed by a [B-tree](https://en.wikipedia.org/wiki/B-tree) of order 5.

  Unlike a set, a bag allows duplicate values — the same value may appear multiple times.
  Elements are kept in ascending Erlang term order. Comparisons use `==` rather than `===` —
  so `1` and `1.0` are treated as the same element.

  ## Pushing vs putting

  Two insert operations are provided:

    * `push/2` — always inserts a new copy, even if the value is already present.
    * `put/2` — inserts only if the value is not already present (idempotent, like `MapSet.put/2`).

  ## Order-statistic operations

  In addition to standard collection operations, `Xb5.Bag` provides:

    * `index_of/2`, `index_of!/2` — 0-based index of a value.
    * `percentile/3`, `percentile_bracket/3` — percentile queries.
    * `percentile_rank/2` — the percentile position of a value.

  Conversion to a sorted list via `to_list/1` always yields elements in ascending order,
  with duplicates preserved.

  ## Erlang interop

  `Xb5.Bag` is compatible with the Erlang `:xb5_bag` module. Build one from an `:xb5_bag`
  term via `new/1`. To go the other way, call `unwrap!/1` to extract the size and root node,
  then pass the result to `:xb5_bag.wrap/1`.

  ## Examples

      iex> bag = Xb5.Bag.new([1, 1, 2, 3])
      Xb5.Bag.new([1, 1, 2, 3])
      iex> Xb5.Bag.member?(bag, 2)
      true
      iex> Xb5.Bag.count(bag, 1)
      2

  """

  ## Types

  @enforce_keys [:size, :root]
  defstruct [:size, :root]

  @type t(value) :: %__MODULE__{size: non_neg_integer(), root: :xb5_bag_node.t(value)}
  @type t :: t(value)
  @type order :: :asc | :desc
  @type value :: term

  ## API

  @doc """
  Finds the element at the given `index` (0-based). Returns `default` if `index` is out of bounds.
  Runs in O(log n) time.

  A negative `index` counts from the end: `-1` is the last element, `-2` the second-to-last, etc.

  This function is an optimized version of `Enum.at/2`.

  ## Examples

      iex> bag = Xb5.Bag.new([1, 2, 3])
      iex> Xb5.Bag.at(bag, 0)
      1
      iex> Xb5.Bag.at(bag, 2)
      3
      iex> Xb5.Bag.at(bag, -1)
      3
      iex> Xb5.Bag.at(bag, 5)
      nil
      iex> Xb5.Bag.at(bag, 5, :missing)
      :missing

  """
  @spec at(t(value), index, default) :: value | default when index: integer, default: term()
  def at(bag, value, default \\ nil)

  def at(%__MODULE__{size: size, root: root}, index, default) when is_integer(index) do
    resolved_index = resolve_index(size, index)

    if resolved_index < 0 or resolved_index >= size do
      default
    else
      :xb5_bag_node.nth(resolved_index + 1, root)
    end
  end

  @doc """
  Returns the number of times `value` appears in `bag`. Values are matched using `==`.

  ## Examples

      iex> bag = Xb5.Bag.new([1, 1, 1, 2, 3])
      iex> Xb5.Bag.count(bag, 1)
      3
      iex> Xb5.Bag.count(bag, 2)
      1
      iex> Xb5.Bag.count(bag, 4)
      0

  """
  @spec count(t(value), value) :: non_neg_integer()
  def count(%__MODULE__{size: size, root: root}, value) do
    case :xb5_bag_node.rank(value, root) do
      :none ->
        0

      rank ->
        case :xb5_bag_node.rank_larger(value, root) do
          [larger_rank | _] ->
            larger_rank - rank

          :none ->
            size - rank + 1
        end
    end
  end

  @doc """
  Removes one occurrence of `value` from the bag. Returns the bag unchanged if `value` is not present.

  ## Examples

      iex> bag = Xb5.Bag.new([1, 1, 2, 3])
      iex> Xb5.Bag.delete(bag, 1)
      Xb5.Bag.new([1, 2, 3])
      iex> Xb5.Bag.delete(bag, 4)
      Xb5.Bag.new([1, 1, 2, 3])

  """
  @spec delete(t(val1), val2) :: t(val1) when val1: value(), val2: value()
  def delete(%__MODULE__{size: size, root: root} = set, value) do
    case :xb5_bag_node.delete_att(value, root) do
      :badkey ->
        set

      root ->
        %{set | size: size - 1, root: root}
    end
  end

  @doc """
  Removes all occurrences of `value` from the bag. Returns the bag unchanged if `value` is not present.

  ## Examples

      iex> bag = Xb5.Bag.new([1, 1, 2, 3])
      iex> Xb5.Bag.delete_all(bag, 1)
      Xb5.Bag.new([2, 3])
      iex> Xb5.Bag.delete_all(bag, 4)
      Xb5.Bag.new([1, 1, 2, 3])

  """
  @spec delete_all(t(val1), val2) :: t(val1) when val1: value(), val2: value()
  def delete_all(%__MODULE__{size: size, root: root} = bag, value) do
    case :xb5_bag_node.delete_att(value, root) do
      :badkey -> bag
      root -> delete_all_recur(value, size - 1, root)
    end
  end

  @doc """
  Returns a new bag containing only elements for which `fun` returns a truthy value.

  ## Examples

      iex> Xb5.Bag.filter(Xb5.Bag.new([1, 2, 3, 4, 5]), fn x -> x > 3 end)
      Xb5.Bag.new([4, 5])

      iex> Xb5.Bag.filter(Xb5.Bag.new([1, 1, 2, 3]), fn x -> rem(x, 2) != 0 end)
      Xb5.Bag.new([1, 1, 3])

  """
  @spec filter(t(a), (a -> as_boolean(term()))) :: t(a) when a: value()
  def filter(set, fun) do
    from_ordered_list(for elem <- to_list(set), fun.(elem), do: elem)
  end

  @doc """
  Returns the 0-based index of `value` in the bag, or `nil` if not present. Runs in O(log n) time.

  ## Examples

      iex> bag = Xb5.Bag.new([1, 2, 3])
      iex> Xb5.Bag.index_of(bag, 1)
      0
      iex> Xb5.Bag.index_of(bag, 3)
      2
      iex> Xb5.Bag.index_of(bag, 4)
      nil

  """
  @spec index_of(t(value), value) :: non_neg_integer | nil
  def index_of(%__MODULE__{root: root}, value) do
    case :xb5_bag_node.rank(value, root) do
      :none -> nil
      rank -> rank - 1
    end
  end

  @doc """
  Returns the 0-based index of `value` in the bag. Raises `KeyError` if not present. Runs in O(log n) time.

  ## Examples

      iex> bag = Xb5.Bag.new([1, 2, 3])
      iex> Xb5.Bag.index_of!(bag, 1)
      0
      iex> Xb5.Bag.index_of!(bag, 3)
      2
      iex> assert_raise KeyError, fn -> Xb5.Bag.index_of!(bag, 4) end

  """
  @spec index_of!(t(value), value) :: non_neg_integer
  def index_of!(%__MODULE__{root: root} = bag, value) do
    case :xb5_bag_node.rank(value, root) do
      :none -> raise KeyError, term: bag, key: value
      rank -> rank - 1
    end
  end

  @doc """
  Returns the smallest element strictly greater than `element`, or `:error` if none exists.

  ## Examples

      iex> bag = Xb5.Bag.new([1, 2, 3])
      iex> Xb5.Bag.larger(bag, 1)
      {:ok, 2}
      iex> Xb5.Bag.larger(bag, 3)
      :error

  """
  @spec larger(t(val), val) :: {:ok, val} | :error when val: value()
  def larger(%__MODULE__{root: root}, element) do
    case :xb5_bag_node.larger(element, root) do
      {:found, e} -> {:ok, e}
      :none -> :error
    end
  end

  @doc """
  Returns the largest element in the bag. Raises `ArgumentError` if the bag is empty.

  ## Examples

      iex> Xb5.Bag.largest!(Xb5.Bag.new([1, 2, 3]))
      3
      iex> Xb5.Bag.largest!(Xb5.Bag.new())
      ** (ArgumentError) bag is empty

  """
  @spec largest!(t(val)) :: val when val: value()
  def largest!(%__MODULE__{size: size, root: root}) do
    if size === 0 do
      raise ArgumentError, "bag is empty"
    else
      :xb5_bag_node.largest(root)
    end
  end

  @doc """
  Checks if `bag` contains `value`. Membership is tested using `==`, not `===`.

  ## Examples

      iex> bag = Xb5.Bag.new([1, 2, 3])
      iex> Xb5.Bag.member?(bag, 2)
      true
      iex> Xb5.Bag.member?(bag, 2.0)
      true
      iex> Xb5.Bag.member?(bag, 4)
      false

  """
  @spec member?(t(), value()) :: boolean()
  def member?(%__MODULE__{root: root}, value) do
    :xb5_bag_node.is_member(value, root)
  end

  @doc """
  Merges two bags into a new bag containing all elements from both, preserving duplicates.

  ## Examples

      iex> Xb5.Bag.merge(Xb5.Bag.new([1, 2, 3]), Xb5.Bag.new([2, 3, 4]))
      Xb5.Bag.new([1, 2, 2, 3, 3, 4])

      iex> Xb5.Bag.merge(Xb5.Bag.new([1, 2]), Xb5.Bag.new())
      Xb5.Bag.new([1, 2])

  """
  @spec merge(t(val1), t(val2)) :: t(val1 | val2) when val1: value(), val2: value()
  def merge(%__MODULE__{size: size1, root: root1}, %__MODULE__{size: size2, root: root2}) do
    size = size1 + size2
    root = :xb5_bag_node.merge(size1, root1, size2, root2)
    %__MODULE__{size: size, root: root}
  end

  @doc """
  Returns a new empty bag.

  ## Examples

      iex> Xb5.Bag.new()
      Xb5.Bag.new([])

  """
  @spec new() :: t()
  def new() do
    %__MODULE__{size: 0, root: :xb5_bag_node.new()}
  end

  @doc """
  Creates a bag from an Erlang `:xb5_bag` term or an enumerable.

  When given an enumerable, elements are stored in ascending order with duplicates preserved.
  When given an Erlang `:xb5_bag` term, the underlying structure is reused directly.

  ## Examples

      iex> Xb5.Bag.new([1, 1, 2, 3])
      Xb5.Bag.new([1, 1, 2, 3])

      iex> Xb5.Bag.new([3, :a, :b, :b])
      Xb5.Bag.new([3, :a, :b, :b])

  """
  @spec new(:xb5_bag.bag(val) | Enumerable.t()) :: t(val) when val: value()
  def new(input) do
    case :xb5_bag.unwrap(input) do
      {:ok, %{size: size, root: root}} ->
        %__MODULE__{size: size, root: root}

      {:error, _} ->
        input
        |> Enum.to_list()
        |> :lists.sort()
        |> from_ordered_list()
    end
  end

  @doc """
  Creates a bag from an Erlang `:xb5_bag` term or an enumerable via the transformation function.

  ## Examples

      iex> Xb5.Bag.new([1, 1, 2], fn x -> x * 2 end)
      Xb5.Bag.new([2, 2, 4])

  """
  @spec new(:xb5_bag.bag() | Enumerable.t(), (term() -> val)) :: t(val) when val: value()
  def new(input, transform) do
    case :xb5_bag.unwrap(input) do
      {:ok, %{root: root}} ->
        transform
        |> :xb5_bag_node.map_to_list(root)
        |> :lists.sort()
        |> from_ordered_list()

      {:error, _} ->
        input
        |> Enum.map(transform)
        |> :lists.sort()
        |> from_ordered_list()
    end
  end

  @doc """
  Returns the percentile value for the given `percentile` (0.0–1.0) using the given method options.
  Returns `nil` if the bag is empty or the percentile is out of range for the chosen method.
  Runs in O(log n) time.

  ## Examples

      iex> bag = Xb5.Bag.new([1, 2, 3, 4])
      iex> Xb5.Bag.percentile(bag, 0.0)
      1
      iex> Xb5.Bag.percentile(bag, 0.5)
      2.5
      iex> Xb5.Bag.percentile(bag, 1.0)
      4
      iex> Xb5.Bag.percentile(Xb5.Bag.new(), 0.5)
      nil

  """
  @spec percentile(t(value), percentile, opts) :: (value | interpolation_result) | nil
        when percentile: :xb5_bag_utils.percentile(),
             opts: [:xb5_bag_utils.percentile_bracket_opt()],
             interpolation_result: number

  def percentile(bag, percentile, opts \\ [])

  def percentile(%__MODULE__{size: size, root: root}, percentile, opts) do
    value_fun = fn value -> value end

    case :xb5_bag_utils.percentile(percentile, size, root, value_fun, opts) do
      :none -> nil
      result -> result
    end
  end

  @doc """
  Returns the percentile bracket for the given `percentile`, or `nil` if the bag is empty or the
  percentile is out of range for the chosen method. Runs in O(log n) time.

  ## Examples

      iex> bag = Xb5.Bag.new([1, 2, 3, 4])
      iex> Xb5.Bag.percentile_bracket(bag, 0.0)
      {:exact, 1}
      iex> Xb5.Bag.percentile_bracket(bag, 0.5)
      {:between, 2, 3, 0.5000000000000001}
      iex> Xb5.Bag.percentile_bracket(bag, 1.0)
      {:exact, 4}
      iex> Xb5.Bag.percentile_bracket(Xb5.Bag.new(), 0.5)
      nil

  """
  @spec percentile_bracket(t(value), percentile, opts) ::
          {:exact, value} | {:between, value, value, float} | nil
        when percentile: :xb5_bag_utils.percentile(),
             opts: [:xb5_bag_utils.percentile_bracket_opt()]

  def percentile_bracket(bag, percentile, opts \\ [])

  def percentile_bracket(%__MODULE__{size: size, root: root}, percentile, opts) do
    case :xb5_bag_utils.percentile_bracket(percentile, size, root, opts) do
      :none -> nil
      result -> result
    end
  end

  @doc """
  Returns the percentile rank of `value` in the bag as a float in 0.0–1.0. Runs in O(log n) time.
  Raises `ArgumentError` if the bag is empty.

  ## Examples

      iex> bag = Xb5.Bag.new([1, 2, 3, 4, 5])
      iex> Xb5.Bag.percentile_rank(bag, 3)
      0.5
      iex> Xb5.Bag.percentile_rank(bag, 1)
      0.1
      iex> Xb5.Bag.percentile_rank(Xb5.Bag.new(), 1)
      ** (ArgumentError) bag is empty

  """
  @spec percentile_rank(t(value), value) :: float
  def percentile_rank(%__MODULE__{size: size, root: root}, value) when size > 0 do
    :xb5_bag_utils.percentile_rank(value, size, root)
  end

  def percentile_rank(%__MODULE__{}, _value) do
    raise ArgumentError, "bag is empty"
  end

  @doc """
  Removes and returns the largest element. Raises `ArgumentError` if the bag is empty.

  ## Examples

      iex> bag = Xb5.Bag.new([1, 2, 3])
      iex> Xb5.Bag.pop_largest!(bag)
      {3, Xb5.Bag.new([1, 2])}
      iex> Xb5.Bag.pop_largest!(Xb5.Bag.new())
      ** (ArgumentError) bag is empty

  """
  @spec pop_largest!(t(val)) :: {val, t(val)} when val: value()
  def pop_largest!(%__MODULE__{size: size, root: root} = set) do
    if size === 0 do
      raise ArgumentError, "bag is empty"
    else
      [value | root] = :xb5_bag_node.take_largest(root)
      set = %{set | size: size - 1, root: root}
      {value, set}
    end
  end

  @doc """
  Removes and returns the smallest element. Raises `ArgumentError` if the bag is empty.

  ## Examples

      iex> bag = Xb5.Bag.new([1, 2, 3])
      iex> Xb5.Bag.pop_smallest!(bag)
      {1, Xb5.Bag.new([2, 3])}
      iex> Xb5.Bag.pop_smallest!(Xb5.Bag.new())
      ** (ArgumentError) bag is empty

  """
  @spec pop_smallest!(t(val)) :: {val, t(val)} when val: value()
  def pop_smallest!(%__MODULE__{size: size, root: root} = set) do
    if size === 0 do
      raise ArgumentError, "bag is empty"
    else
      [value | root] = :xb5_bag_node.take_smallest(root)
      set = %{set | size: size - 1, root: root}
      {value, set}
    end
  end

  @doc """
  Adds `value` to the bag, always inserting a new copy even if already present.

  ## Examples

      iex> bag = Xb5.Bag.new([1, 2, 3])
      iex> Xb5.Bag.push(bag, 2)
      Xb5.Bag.new([1, 2, 2, 3])
      iex> Xb5.Bag.push(bag, 4)
      Xb5.Bag.new([1, 2, 3, 4])

  """
  @spec push(t(val), new_val) :: t(val | new_val) when val: value(), new_val: value()
  def push(%__MODULE__{size: size, root: root} = set, value) do
    root = :xb5_bag_node.push(value, root)
    %{set | size: size + 1, root: root}
  end

  @doc """
  Adds `value` to the bag only if it is not already present. Returns the bag unchanged if `value` is present.

  ## Examples

      iex> bag = Xb5.Bag.new([1, 2, 3])
      iex> Xb5.Bag.put(bag, 2)
      Xb5.Bag.new([1, 2, 3])
      iex> Xb5.Bag.put(bag, 4)
      Xb5.Bag.new([1, 2, 3, 4])

  """
  @spec put(t(val), new_val) :: t(val | new_val) when val: value(), new_val: value()
  def put(%__MODULE__{size: size, root: root} = set, value) do
    case :xb5_bag_node.insert_att(value, root) do
      :key_exists ->
        set

      root ->
        %{set | size: size + 1, root: root}
    end
  end

  @doc """
  Returns a new bag containing only elements for which `fun` returns a falsy value.

  ## Examples

      iex> Xb5.Bag.reject(Xb5.Bag.new([1, 2, 3, 4, 5]), fn x -> x > 3 end)
      Xb5.Bag.new([1, 2, 3])

      iex> Xb5.Bag.reject(Xb5.Bag.new([1, 1, 2, 3]), fn x -> rem(x, 2) != 0 end)
      Xb5.Bag.new([2])

  """
  @spec reject(t(a), (a -> as_boolean(term()))) :: t(a) when a: value()
  def reject(set, fun) do
    from_ordered_list(for elem <- to_list(set), !fun.(elem), do: elem)
  end

  @doc """
  Returns the number of elements in the bag, counting duplicates.

  ## Examples

      iex> Xb5.Bag.size(Xb5.Bag.new([1, 2, 3]))
      3
      iex> Xb5.Bag.size(Xb5.Bag.new([1, 1, 2]))
      3
      iex> Xb5.Bag.size(Xb5.Bag.new())
      0

  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{size: size}) do
    size
  end

  @doc """
  Returns the largest element strictly less than `element`, or `:error` if none exists.

  ## Examples

      iex> bag = Xb5.Bag.new([1, 2, 3])
      iex> Xb5.Bag.smaller(bag, 3)
      {:ok, 2}
      iex> Xb5.Bag.smaller(bag, 1)
      :error

  """
  @spec smaller(t(val), val) :: {:ok, val} | :error when val: value()
  def smaller(%__MODULE__{root: root}, element) do
    case :xb5_bag_node.smaller(element, root) do
      {:found, e} -> {:ok, e}
      :none -> :error
    end
  end

  @doc """
  Returns the smallest element in the bag. Raises `ArgumentError` if the bag is empty.

  ## Examples

      iex> Xb5.Bag.smallest!(Xb5.Bag.new([1, 2, 3]))
      1
      iex> Xb5.Bag.smallest!(Xb5.Bag.new())
      ** (ArgumentError) bag is empty

  """
  @spec smallest!(t(val)) :: val when val: value()
  def smallest!(%__MODULE__{size: size, root: root}) do
    if size === 0 do
      raise ArgumentError, "bag is empty"
    else
      :xb5_bag_node.smallest(root)
    end
  end

  @doc """
  Returns a lazy stream over all elements of `bag`.

  `order` controls traversal direction: `:asc` (ascending, the default) or
  `:desc` (descending).

  ## Examples

      iex> bag = Xb5.Bag.new([1, 2, 3])
      iex> Xb5.Bag.stream(bag) |> Enum.to_list()
      [1, 2, 3]
      iex> Xb5.Bag.stream(bag, :desc) |> Enum.to_list()
      [3, 2, 1]
      iex> Xb5.Bag.stream(Xb5.Bag.new()) |> Enum.to_list()
      []

  """
  @spec stream(t(val), order) :: Enumerable.t() when val: value()
  def stream(bag, order \\ :asc)

  def stream(%__MODULE__{root: root}, order) do
    erl_iterator_order = erl_iterator_order(order)

    Stream.resource(
      fn -> :xb5_bag_node.iterator(root, erl_iterator_order) end,
      &stream_next/1,
      &stream_after/1
    )
  end

  @doc """
  Returns a lazy stream over elements of `bag` starting from `element`.

  For `:asc` (the default), starts at the first element greater than or
  equal to `element`. For `:desc`, starts at the first element less than or
  equal to `element`. Returns an empty stream if no such element exists.

  ## Examples

      iex> bag = Xb5.Bag.new([1, 2, 3, 4, 5])
      iex> Xb5.Bag.stream_from(bag, 3) |> Enum.to_list()
      [3, 4, 5]
      iex> Xb5.Bag.stream_from(bag, 3, :desc) |> Enum.to_list()
      [3, 2, 1]
      iex> Xb5.Bag.stream_from(bag, 6) |> Enum.to_list()
      []

  """
  @spec stream_from(t(val), val, order) :: Enumerable.t() when val: value()
  def stream_from(bag, value, order \\ :asc)

  def stream_from(%__MODULE__{root: root}, value, order) do
    erl_iterator_order = erl_iterator_order(order)

    Stream.resource(
      fn -> :xb5_bag_node.iterator_from(value, root, erl_iterator_order) end,
      &stream_next/1,
      &stream_after/1
    )
  end

  @doc """
  Returns a lazy stream over elements of `bag` starting from `index` (0-based),
  always in ascending order.

  A negative `index` counts from the end: `-1` starts at the last element.
  Returns an empty stream if `index` is out of bounds.

  ## Examples

      iex> bag = Xb5.Bag.new([1, 2, 3, 4, 5])
      iex> Xb5.Bag.stream_from_index(bag, 2) |> Enum.to_list()
      [3, 4, 5]
      iex> Xb5.Bag.stream_from_index(bag, -2) |> Enum.to_list()
      [4, 5]
      iex> Xb5.Bag.stream_from_index(bag, 10) |> Enum.to_list()
      []

  """
  @spec stream_from_index(t(val), integer) :: Enumerable.t() when val: value()
  def stream_from_index(%__MODULE__{root: root, size: size}, index) when is_integer(index) do
    resolved_index = resolve_index(size, index)

    if resolved_index < 0 or resolved_index >= size do
      Stream.resource(
        fn -> :ok end,
        fn iter -> {:halt, iter} end,
        fn _iter -> :ok end
      )
    else
      rank = resolved_index + 1

      Stream.resource(
        fn -> :xb5_bag_node.iterator_from_nth(rank, size, root, :ordered) end,
        &stream_next/1,
        &stream_after/1
      )
    end
  end

  @doc """
  Returns structural statistics about the underlying B-tree.

  Useful for inspecting tree balance and node utilization.

  ## Examples

      iex> Xb5.Bag.structural_stats(Xb5.Bag.new(1..100))
      [
        height: 4,
        node_counts: [
          internal4: 2,
          internal3: 3,
          internal2: 3,
          internal1: 1,
          leaf4: 6,
          leaf3: 14,
          leaf2: 5,
          leaf1: 0
        ],
        node_percentages: [
          internal4: 5.9,
          internal3: 8.8,
          internal2: 8.8,
          internal1: 2.9,
          leaf4: 17.6,
          leaf3: 41.2,
          leaf2: 14.7,
          leaf1: 0.0
        ],
        total_keys: 100,
        key_percentages: [
          internal4: 8.0,
          internal3: 9.0,
          internal2: 6.0,
          internal1: 1.0,
          leaf4: 24.0,
          leaf3: 42.0,
          leaf2: 10.0,
          leaf1: 0.0
        ],
        avg_keys_per_node: 2.9411764705882355,
        avg_keys_per_internal_node: 2.6666666666666665,
        avg_keys_per_leaf_node: 3.04
      ]


  """
  @spec structural_stats(t()) :: :xb5_structural_stats.t()
  def structural_stats(%__MODULE__{root: root}) do
    :xb5_bag_node.structural_stats(root)
  end

  @doc """
  Returns all elements as a sorted list, with duplicates.

  ## Examples

      iex> Xb5.Bag.to_list(Xb5.Bag.new([1, 2, 3]))
      [1, 2, 3]
      iex> Xb5.Bag.to_list(Xb5.Bag.new([1, 1, 2]))
      [1, 1, 2]

  """
  @spec to_list(t(val)) :: [val] when val: value()
  def to_list(%__MODULE__{root: root}) do
    :xb5_bag_node.to_list(root)
  end

  @doc """
  Returns the size and root node of `bag` as `%{size: n, root: node}`.
  Pass the result to `:xb5_bag.wrap/1` to obtain a proper `:xb5_bag` term.

  ## Examples

      iex> bag = Xb5.Bag.new([1, 1, 2, 3])
      iex> %{size: size} = Xb5.Bag.unwrap!(bag)
      iex> size
      4

  """
  @spec unwrap!(t(val)) :: :xb5_bag.unwrapped_bag(val) when val: value()
  def unwrap!(%__MODULE__{size: size, root: root}) do
    %{size: size, root: root}
  end

  ## Internal

  defp delete_all_recur(value, size, root) do
    case :xb5_bag_node.delete_att(value, root) do
      :badkey -> %__MODULE__{size: size, root: root}
      root -> delete_all_recur(value, size - 1, root)
    end
  end

  defp from_ordered_list(list) do
    size = length(list)
    root = :xb5_bag_node.from_ordered_list(size, list)
    %__MODULE__{size: size, root: root}
  end

  defp resolve_index(size, index) do
    if index < 0 do
      size + index
    else
      index
    end
  end

  ##

  defp erl_iterator_order(:asc), do: :ordered
  defp erl_iterator_order(:desc), do: :reversed

  defp stream_next(iter) do
    case :xb5_bag_node.next(iter) do
      {value, iter} ->
        {[value], iter}

      :none ->
        {:halt, iter}
    end
  end

  defp stream_after(_iter) do
    :ok
  end

  ## Protocols - Enumerable

  defimpl Enumerable do
    def count(bag) do
      {:ok, Xb5.Bag.size(bag)}
    end

    def member?(bag, val) do
      # NOTE: not strict comparison
      {:ok, Xb5.Bag.member?(bag, val)}
    end

    def slice(%Xb5.Bag{size: bag_size, root: root}) do
      {:ok, bag_size, &:xb5_bag_node.elixir_slice(&1, &2, &3, bag_size, root)}
    end

    def reduce(%Xb5.Bag{root: root}, acc, fun) do
      :xb5_bag_node.elixir_reduce(fun, acc, root)
    end
  end

  ## Protocols - Collectable

  defimpl Collectable do
    def into(%@for{} = bag) do
      fun = fn
        list, {:cont, x} -> [x | list]
        list, :done -> Xb5.Bag.merge(bag, Xb5.Bag.new(list))
        _, :halt -> :ok
      end

      {[], fun}
    end
  end

  ## Protocols - Inspect

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(bag, %Inspect.Opts{} = opts) do
      {doc, %{limit: limit}} =
        bag
        |> Xb5.Bag.to_list()
        |> to_doc_with_opts(%{opts | charlists: :as_lists})

      {concat(["Xb5.Bag.new(", doc, ")"]), %{opts | limit: limit}}
    end
  end
end
