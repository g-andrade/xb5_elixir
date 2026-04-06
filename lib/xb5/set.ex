defmodule Xb5.Set do
  @moduledoc """
  An ordered set backed by a [B-tree](https://en.wikipedia.org/wiki/B-tree) of order 5.

  Elements are kept in ascending Erlang term order, and each value appears at most once.
  Comparisons use `==` rather than `===` — so `1` and `1.0` are treated as the same
  element, unlike `MapSet`.

  ## Comparison with `MapSet`

  `Xb5.Set` supports the same operations as `MapSet` — `union/2`, `intersection/2`,
  `difference/2`, `subset?/2`, and so on — and additionally offers O(log n) access to
  ordered extremes and neighbors:

    * `first/2`, `last/2` — return the min/max element, or a default.
    * `first!/1`, `last!/1` — return the min/max element, raising on empty.
    * `higher/2`, `lower/2` — find the nearest element above or below a given value.
    * `pop_first!/1`, `pop_last!/1` — remove and return endpoint elements.

  Conversion to a sorted list via `to_list/1` always yields elements in ascending order.

  ## Erlang interop

  `Xb5.Set` is compatible with the Erlang `:xb5_sets` module. Build one from an
  `:xb5_sets` term via `new/1`. To go the other way, call `unwrap!/1` to extract the
  size and root node, then pass the result to `:xb5_sets.wrap/1`.

  ## Examples

      iex> set = Xb5.Set.new([3, 1, 2, 1])
      Xb5.Set.new([1, 2, 3])
      iex> Xb5.Set.member?(set, 2)
      true
      iex> Xb5.Set.last!(set)
      3

  """

  ## Types

  @enforce_keys [:size, :root]
  defstruct [:size, :root]

  @type t(value) :: %__MODULE__{size: non_neg_integer(), root: :xb5_sets_node.t(value)}
  @type t :: t(value)
  @type order :: :asc | :desc
  @type value :: term

  ## API

  @doc """
  Deletes `value` from `set`.

  Returns a new set which is a copy of `set` but without `value`.

  ## Examples

      iex> set = Xb5.Set.new([1, 2, 3])
      iex> Xb5.Set.delete(set, 4)
      Xb5.Set.new([1, 2, 3])
      iex> Xb5.Set.delete(set, 2)
      Xb5.Set.new([1, 3])

  """
  @spec delete(t(val1), val2) :: t(val1) when val1: value(), val2: value()
  def delete(%__MODULE__{size: size, root: root} = set, value) do
    case :xb5_sets_node.delete_att(value, root) do
      :badkey ->
        set

      root ->
        %{set | size: size - 1, root: root}
    end
  end

  @doc """
  Returns a set that is `set1` without the members of `set2`.

  ## Examples

      iex> Xb5.Set.difference(Xb5.Set.new([1, 2]), Xb5.Set.new([2, 3, 4]))
      Xb5.Set.new([1])

  """
  @spec difference(t(val1), t(val2)) :: t(val1) when val1: value(), val2: value()
  def difference(%__MODULE__{size: size1, root: root1}, %__MODULE__{size: size2, root: root2}) do
    [size | root] = :xb5_sets_node.difference(size1, root1, size2, root2)
    %__MODULE__{size: size, root: root}
  end

  @doc """
  Checks if `set1` and `set2` have no members in common.

  ## Examples

      iex> Xb5.Set.disjoint?(Xb5.Set.new([1, 2]), Xb5.Set.new([3, 4]))
      true
      iex> Xb5.Set.disjoint?(Xb5.Set.new([1, 2]), Xb5.Set.new([2, 3]))
      false

  """
  @spec disjoint?(t(), t()) :: boolean()
  def disjoint?(%__MODULE__{size: size1, root: root1}, %__MODULE__{size: size2, root: root2}) do
    :xb5_sets_node.is_disjoint(size1, root1, size2, root2)
  end

  @doc """
  Checks if two sets are equal.

  The comparison between elements is done using `==`, so for example
  `Xb5.Set.new([1])` is equal to `Xb5.Set.new([1.0])`.

  ## Examples

      iex> Xb5.Set.equal?(Xb5.Set.new([1, 2]), Xb5.Set.new([2, 1, 1]))
      true
      iex> Xb5.Set.equal?(Xb5.Set.new([1, 2]), Xb5.Set.new([3, 4]))
      false
      iex> Xb5.Set.equal?(Xb5.Set.new([1]), Xb5.Set.new([1.0]))
      true

  """
  @spec equal?(t(), t()) :: boolean()
  def equal?(%__MODULE__{size: size1, root: root1}, %__MODULE__{size: size2, root: root2}) do
    :xb5_sets_node.is_equal(size1, root1, size2, root2)
  end

  @doc """
  Filters `set` by returning only elements for which `fun` returns a truthy value.

  Also see `reject/2` which discards all elements where the function returns
  a truthy value.

  ## Examples

      iex> Xb5.Set.filter(Xb5.Set.new(1..5), fn x -> x > 3 end)
      Xb5.Set.new([4, 5])

      iex> Xb5.Set.filter(Xb5.Set.new(["a", :b, "c"]), &is_atom/1)
      Xb5.Set.new([:b])

  """
  @spec filter(t(a), (a -> as_boolean(term()))) :: t(a) when a: value()
  def filter(set, fun) do
    from_ordset(for elem <- to_list(set), fun.(elem), do: elem)
  end

  @doc """
  Returns the first (smallest) element in `set`, or `default` if `set` is empty.

  ## Examples

      iex> Xb5.Set.first(Xb5.Set.new([1, 2, 3]))
      1
      iex> Xb5.Set.first(Xb5.Set.new())
      nil
      iex> Xb5.Set.first(Xb5.Set.new(), :empty)
      :empty

  """
  @spec first(t(value), default) :: value | default when default: term()
  def first(set, default \\ nil)

  def first(%__MODULE__{size: size, root: root}, default) do
    if size === 0, do: default, else: :xb5_sets_node.smallest(root)
  end

  @doc """
  Returns the first (smallest) element in `set`.

  Raises `Xb5.EmptyError` if `set` is empty.

  ## Examples

      iex> Xb5.Set.first!(Xb5.Set.new([1, 2, 3]))
      1
      iex> Xb5.Set.first!(Xb5.Set.new())
      ** (Xb5.EmptyError) empty error

  """
  @spec first!(t(value)) :: value
  def first!(%__MODULE__{size: size, root: root}) do
    if size === 0, do: raise(Xb5.EmptyError), else: :xb5_sets_node.smallest(root)
  end

  @doc """
  Returns the immediate successor of `value` in `set`.

  If `set` contains an element strictly greater than `value`, it is returned as
  `{:ok, next}`. Otherwise returns `:error`.

  ## Examples

      iex> Xb5.Set.higher(Xb5.Set.new([1, 2, 3]), 2)
      {:ok, 3}
      iex> Xb5.Set.higher(Xb5.Set.new([1, 2, 3]), 3)
      :error

  """
  @spec higher(t(value), value) :: {:ok, value} | :error
  def higher(%__MODULE__{root: root}, value) do
    case :xb5_sets_node.larger(value, root) do
      {:found, e} -> {:ok, e}
      :none -> :error
    end
  end

  @doc """
  Returns a set containing only members that `set1` and `set2` have in common.

  ## Examples

      iex> Xb5.Set.intersection(Xb5.Set.new([1, 2]), Xb5.Set.new([2, 3, 4]))
      Xb5.Set.new([2])

      iex> Xb5.Set.intersection(Xb5.Set.new([1, 2]), Xb5.Set.new([3, 4]))
      Xb5.Set.new([])

  """
  @spec intersection(t(value), t(value)) :: t(value)
  def intersection(%__MODULE__{size: size1, root: root1}, %__MODULE__{size: size2, root: root2}) do
    [size | root] = :xb5_sets_node.intersection(size1, root1, size2, root2)
    %__MODULE__{size: size, root: root}
  end

  @doc """
  Returns the last (largest) element in `set`, or `default` if `set` is empty.

  ## Examples

      iex> Xb5.Set.last(Xb5.Set.new([1, 2, 3]))
      3
      iex> Xb5.Set.last(Xb5.Set.new())
      nil
      iex> Xb5.Set.last(Xb5.Set.new(), :empty)
      :empty

  """
  @spec last(t(value), default) :: value | default when default: term()
  def last(set, default \\ nil)

  def last(%__MODULE__{size: size, root: root}, default) do
    if size === 0, do: default, else: :xb5_sets_node.largest(root)
  end

  @doc """
  Returns the last (largest) element in `set`.

  Raises `Xb5.EmptyError` if `set` is empty.

  ## Examples

      iex> Xb5.Set.last!(Xb5.Set.new([1, 2, 3]))
      3
      iex> Xb5.Set.last!(Xb5.Set.new())
      ** (Xb5.EmptyError) empty error

  """
  @spec last!(t(value)) :: value
  def last!(%__MODULE__{size: size, root: root}) do
    if size === 0, do: raise(Xb5.EmptyError), else: :xb5_sets_node.largest(root)
  end

  @doc """
  Returns the immediate predecessor of `value` in `set`.

  If `set` contains an element strictly less than `value`, it is returned as
  `{:ok, prev}`. Otherwise returns `:error`.

  ## Examples

      iex> Xb5.Set.lower(Xb5.Set.new([1, 2, 3]), 2)
      {:ok, 1}
      iex> Xb5.Set.lower(Xb5.Set.new([1, 2, 3]), 1)
      :error

  """
  @spec lower(t(value), value) :: {:ok, value} | :error
  def lower(%__MODULE__{root: root}, value) do
    case :xb5_sets_node.smaller(value, root) do
      {:found, e} -> {:ok, e}
      :none -> :error
    end
  end

  @doc """
  Applies `fun` to each element and returns a new set built from the results.

  Because the mapped elements may not be unique, they are deduplicated.

  ## Examples

      iex> Xb5.Set.map(Xb5.Set.new([1, 2, 3]), fn x -> x * 2 end)
      Xb5.Set.new([2, 4, 6])
      iex> Xb5.Set.map(Xb5.Set.new([1, 2, 3]), fn _ -> :same end)
      Xb5.Set.new([:same])

  """
  @spec map(t(a), (a -> b)) :: t(b) when a: value(), b: value()
  def map(%__MODULE__{root: root}, fun) do
    list = :xb5_sets_node.map_to_list(fun, root)
    deduped = :lists.usort(list)
    from_ordset(length(deduped), deduped)
  end

  @doc """
  Checks if `set` contains `value`.

  Membership is tested using `==`, not `===`, so for example `member?(set, 1.0)` will
  match an element `1`.

  ## Examples

      iex> Xb5.Set.member?(Xb5.Set.new([1, 2, 3]), 2)
      true
      iex> Xb5.Set.member?(Xb5.Set.new([1, 2, 3]), 4)
      false

  """
  @spec member?(t(), value()) :: boolean()
  def member?(%__MODULE__{root: root}, value) do
    :xb5_sets_node.is_member(value, root)
  end

  @doc """
  Returns a new empty set.

  ## Examples

      iex> Xb5.Set.new()
      Xb5.Set.new([])

  """
  @spec new() :: t()
  def new() do
    %__MODULE__{size: 0, root: :xb5_sets_node.new()}
  end

  @doc """
  Creates a set from an Erlang `:xb5_sets` term or an enumerable.

  When given an enumerable, elements are deduplicated and stored in ascending order.
  When given an Erlang `:xb5_sets` term, the underlying structure is reused directly.

  ## Examples

      iex> Xb5.Set.new([:b, :a, 3])
      Xb5.Set.new([3, :a, :b])
      iex> Xb5.Set.new([3, 3, 3, 2, 2, 1])
      Xb5.Set.new([1, 2, 3])

  """
  @spec new(:xb5_sets.set(value) | Enumerable.t()) :: t(value)
  def new(input) do
    case :xb5_sets.unwrap(input) do
      {:ok, %{size: size, root: root}} ->
        %__MODULE__{size: size, root: root}

      {:error, _} ->
        input
        |> Enum.to_list()
        |> :lists.usort()
        |> from_ordset()
    end
  end

  @doc """
  Creates a set from an Erlang `:xb5_sets` term or an enumerable via the transformation function.

  The results of `transform` are deduplicated and stored in ascending order.

  ## Examples

      iex> Xb5.Set.new([1, 2, 1], fn x -> 2 * x end)
      Xb5.Set.new([2, 4])

  """
  @spec new(:xb5_sets.set() | Enumerable.t(), (term() -> value)) :: t(value)
  def new(input, transform) do
    case :xb5_sets.unwrap(input) do
      {:ok, %{root: root}} ->
        transform
        |> :xb5_sets_node.map_to_list(root)
        |> :lists.usort()
        |> from_ordset()

      {:error, _} ->
        input
        |> Enum.map(transform)
        |> :lists.usort()
        |> from_ordset()
    end
  end

  @doc """
  Removes and returns `{value, updated_set}` for the first (smallest) element in `set`.

  Raises `Xb5.EmptyError` if `set` is empty.

  ## Examples

      iex> Xb5.Set.pop_first!(Xb5.Set.new([1, 2, 3]))
      {1, Xb5.Set.new([2, 3])}
      iex> Xb5.Set.pop_first!(Xb5.Set.new())
      ** (Xb5.EmptyError) empty error

  """
  @spec pop_first!(t(value)) :: {value, t(value)}
  def pop_first!(%__MODULE__{size: size, root: root} = set) do
    if size === 0 do
      raise Xb5.EmptyError
    else
      [value | root] = :xb5_sets_node.take_smallest(root)
      set = %{set | size: size - 1, root: root}
      {value, set}
    end
  end

  @doc """
  Removes and returns `{value, updated_set}` for the last (largest) element in `set`.

  Raises `Xb5.EmptyError` if `set` is empty.

  ## Examples

      iex> Xb5.Set.pop_last!(Xb5.Set.new([1, 2, 3]))
      {3, Xb5.Set.new([1, 2])}
      iex> Xb5.Set.pop_last!(Xb5.Set.new())
      ** (Xb5.EmptyError) empty error

  """
  @spec pop_last!(t(value)) :: {value, t(value)}
  def pop_last!(%__MODULE__{size: size, root: root} = set) do
    if size === 0 do
      raise Xb5.EmptyError
    else
      [value | root] = :xb5_sets_node.take_largest(root)
      set = %{set | size: size - 1, root: root}
      {value, set}
    end
  end

  @doc """
  Inserts `value` into `set` if `set` doesn't already contain it.

  ## Examples

      iex> Xb5.Set.put(Xb5.Set.new([1, 2, 3]), 3)
      Xb5.Set.new([1, 2, 3])
      iex> Xb5.Set.put(Xb5.Set.new([1, 2, 3]), 4)
      Xb5.Set.new([1, 2, 3, 4])

  """
  @spec put(t(value), new_value) :: t(value | new_value) when new_value: value()
  def put(%__MODULE__{size: size, root: root} = set, value) do
    case :xb5_sets_node.insert_att(value, root) do
      :key_exists ->
        set

      root ->
        %{set | size: size + 1, root: root}
    end
  end

  @doc """
  Returns a set by excluding the elements from `set` for which `fun` returns a truthy value.

  See also `filter/2`.

  ## Examples

      iex> Xb5.Set.reject(Xb5.Set.new(1..5), fn x -> rem(x, 2) != 0 end)
      Xb5.Set.new([2, 4])

      iex> Xb5.Set.reject(Xb5.Set.new(["a", :b, "c"]), &is_atom/1)
      Xb5.Set.new(["a", "c"])

  """
  @spec reject(t(a), (a -> as_boolean(term()))) :: t(a) when a: value()
  def reject(set, fun) do
    from_ordset(for elem <- to_list(set), !fun.(elem), do: elem)
  end

  @doc """
  Returns the number of elements in `set`.

  ## Examples

      iex> Xb5.Set.size(Xb5.Set.new([1, 2, 3]))
      3

  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{size: size}) do
    size
  end

  @doc """
  Splits `set` into two sets according to the given function `fun`.

  Returns a tuple with the first set containing all elements for which `fun` returned
  a truthy value, and a second set with all elements for which `fun` returned a falsy
  value (`false` or `nil`).

  ## Examples

      iex> {while_true, while_false} = Xb5.Set.split_with(Xb5.Set.new([1, 2, 3, 4]), fn v -> rem(v, 2) == 0 end)
      iex> while_true
      Xb5.Set.new([2, 4])
      iex> while_false
      Xb5.Set.new([1, 3])

      iex> {while_true, while_false} = Xb5.Set.split_with(Xb5.Set.new(), fn v -> v > 50 end)
      iex> while_true
      Xb5.Set.new([])
      iex> while_false
      Xb5.Set.new([])

  """
  @spec split_with(t(), (term() -> as_boolean(term()))) :: {t(), t()}
  def split_with(%__MODULE__{root: root}, fun) do
    root
    |> :xb5_sets_node.to_rev_list()
    |> split_with_recur(fun, 0, [], 0, [])
  end

  @doc """
  Returns a lazy stream over all elements of `set`.

  `order` controls traversal direction: `:asc` (ascending, the default) or
  `:desc` (descending).

  ## Examples

      iex> set = Xb5.Set.new([1, 2, 3])
      iex> Xb5.Set.stream(set) |> Enum.to_list()
      [1, 2, 3]
      iex> Xb5.Set.stream(set, :desc) |> Enum.to_list()
      [3, 2, 1]
      iex> Xb5.Set.stream(Xb5.Set.new()) |> Enum.to_list()
      []

  """
  @spec stream(t(value), order) :: Enumerable.t()
  def stream(set, order \\ :asc)

  def stream(%__MODULE__{root: root}, order) do
    erl_iterator_order = erl_iterator_order(order)

    Stream.resource(
      fn -> :xb5_sets_node.iterator(root, erl_iterator_order) end,
      &stream_next/1,
      &stream_after/1
    )
  end

  @doc """
  Returns a lazy stream over elements of `set` starting from `value`.

  For `:asc` (the default), starts at the first element greater than or
  equal to `value`. For `:desc`, starts at the first element less than or
  equal to `value`. Returns an empty stream if no such element exists.

  ## Examples

      iex> set = Xb5.Set.new([1, 2, 3, 4, 5])
      iex> Xb5.Set.stream_from(set, 3) |> Enum.to_list()
      [3, 4, 5]
      iex> Xb5.Set.stream_from(set, 3, :desc) |> Enum.to_list()
      [3, 2, 1]
      iex> Xb5.Set.stream_from(set, 6) |> Enum.to_list()
      []

  """
  @spec stream_from(t(value), value, order) :: Enumerable.t()
  def stream_from(set, value, order \\ :asc)

  def stream_from(%__MODULE__{root: root}, value, order) do
    erl_iterator_order = erl_iterator_order(order)

    Stream.resource(
      fn -> :xb5_sets_node.iterator_from(value, root, erl_iterator_order) end,
      &stream_next/1,
      &stream_after/1
    )
  end

  @doc """
  Returns structural statistics about the underlying B-tree.

  Useful for inspecting tree balance and node utilization.

  ## Examples

      iex> Xb5.Set.structural_stats(Xb5.Set.new(1..100))
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
    :xb5_sets_node.structural_stats(root)
  end

  @doc """
  Checks if `set1`'s members are all contained in `set2`.

  This function checks if `set1` is a subset of `set2`.

  ## Examples

      iex> Xb5.Set.subset?(Xb5.Set.new([1, 2]), Xb5.Set.new([1, 2, 3]))
      true
      iex> Xb5.Set.subset?(Xb5.Set.new([1, 2, 3]), Xb5.Set.new([1, 2]))
      false

  """
  @spec subset?(t(), t()) :: boolean()
  def subset?(%__MODULE__{size: size1, root: root1}, %__MODULE__{size: size2, root: root2}) do
    :xb5_sets_node.is_subset(size1, root1, size2, root2)
  end

  @doc """
  Returns a set with elements that are present in only one but not both sets.

  Implemented as `union(difference(set1, set2), difference(set2, set1))`.

  ## Examples

      iex> Xb5.Set.symmetric_difference(Xb5.Set.new([1, 2, 3]), Xb5.Set.new([2, 3, 4]))
      Xb5.Set.new([1, 4])

  """
  @spec symmetric_difference(t(val1), t(val2)) :: t(val1 | val2) when val1: value(), val2: value()
  def symmetric_difference(set1, set2) do
    union(difference(set1, set2), difference(set2, set1))
  end

  @doc """
  Converts `set` to a sorted list.

  ## Examples

      iex> Xb5.Set.to_list(Xb5.Set.new([1, 2, 3]))
      [1, 2, 3]

  """
  @spec to_list(t(value)) :: [value]
  def to_list(%__MODULE__{root: root}) do
    :xb5_sets_node.to_list(root)
  end

  @doc """
  Returns a set containing all members of `set1` and `set2`.

  ## Examples

      iex> Xb5.Set.union(Xb5.Set.new([1, 2]), Xb5.Set.new([2, 3, 4]))
      Xb5.Set.new([1, 2, 3, 4])

  """
  @spec union(t(val1), t(val2)) :: t(val1 | val2) when val1: value(), val2: value()
  def union(%__MODULE__{size: size1, root: root1}, %__MODULE__{size: size2, root: root2}) do
    [size | root] = :xb5_sets_node.union(size1, root1, size2, root2)
    %__MODULE__{size: size, root: root}
  end

  @doc """
  Returns the size and root node of `set` as `%{size: n, root: node}`.

  Pass the result to `:xb5_sets.wrap/1` to obtain a proper `:xb5_sets` term.

  ## Examples

      iex> %{size: size} = Xb5.Set.unwrap!(Xb5.Set.new([1, 2, 3]))
      iex> size
      3

  """
  @spec unwrap!(t(value)) :: :xb5_sets.unwrapped_set(value)
  def unwrap!(%__MODULE__{size: size, root: root}) do
    %{size: size, root: root}
  end

  ## Internal

  defp from_ordset(ordset) do
    size = length(ordset)
    from_ordset(size, ordset)
  end

  defp from_ordset(size, ordset) do
    root = :xb5_sets_node.from_ordset(size, ordset)
    %__MODULE__{size: size, root: root}
  end

  ##

  defp erl_iterator_order(:asc), do: :ordered
  defp erl_iterator_order(:desc), do: :reversed

  defp stream_next(iter) do
    case :xb5_sets_node.next(iter) do
      {value, iter} ->
        {[value], iter}

      :none ->
        {:halt, iter}
    end
  end

  defp stream_after(_iter) do
    :ok
  end

  ##

  defp split_with_recur([h | t], fun, size1, acc1, size2, acc2) do
    if fun.(h) do
      split_with_recur(t, fun, size1 + 1, [h | acc1], size2, acc2)
    else
      split_with_recur(t, fun, size1, acc1, size2 + 1, [h | acc2])
    end
  end

  defp split_with_recur([], _fun, size1, acc1, size2, acc2) do
    # acc1 and acc2 were accumulated in order, they're ready for a rebuild
    {from_ordset(size1, acc1), from_ordset(size2, acc2)}
  end

  ## Protocols - Enumerable

  defimpl Enumerable do
    def count(set) do
      {:ok, Xb5.Set.size(set)}
    end

    def member?(set, value) do
      # NOTE: not strict comparison
      {:ok, Xb5.Set.member?(set, value)}
    end

    def slice(set) do
      size = Xb5.Set.size(set)
      {:ok, size, &Xb5.Set.to_list/1}
    end

    def reduce(set, acc, fun) do
      %Xb5.Set{root: root} = set
      :xb5_sets_node.elixir_reduce(fun, acc, root)
    end
  end

  ## Protocols - Collectable

  defimpl Collectable do
    def into(%@for{} = set) do
      fun = fn
        list, {:cont, x} -> [x | list]
        list, :done -> Xb5.Set.union(set, Xb5.Set.new(list))
        _, :halt -> :ok
      end

      {[], fun}
    end
  end

  ## Protocols - Inspect

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(set, %Inspect.Opts{} = opts) do
      {doc, %{limit: limit}} =
        set
        |> Xb5.Set.to_list()
        |> to_doc_with_opts(%{opts | charlists: :as_lists})

      {concat(["Xb5.Set.new(", doc, ")"]), %{opts | limit: limit}}
    end
  end
end
