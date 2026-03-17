defmodule Xb5.Set do
  ## Types

  @enforce_keys [:size, :root]
  defstruct [:size, :root]

  @type t(value) :: %__MODULE__{size: non_neg_integer(), root: :xb5_sets_node.t(value)}
  @type t :: t(value)
  @type value :: term

  ## API

  @spec delete(t(val1), val2) :: t(val1) when val1: value(), val2: value()
  def delete(%__MODULE__{size: size, root: root} = set, value) do
    case :xb5_sets_node.delete_att(value, root) do
      :badkey ->
        set

      root ->
        %{set | size: size - 1, root: root}
    end
  end

  @spec difference(t(val1), t(val2)) :: t(val1) when val1: value(), val2: value()
  def difference(%__MODULE__{size: size1, root: root1}, %__MODULE__{size: size2, root: root2}) do
    [size | root] = :xb5_sets_node.difference(size1, root1, size2, root2)
    %__MODULE__{size: size, root: root}
  end

  @spec disjoint?(t(), t()) :: boolean()
  def disjoint?(%__MODULE__{size: size1, root: root1}, %__MODULE__{size: size2, root: root2}) do
    :xb5_sets_node.is_disjoint(size1, root1, size2, root2)
  end

  @spec equal?(t(), t()) :: boolean()
  def equal?(%__MODULE__{size: size1, root: root1}, %__MODULE__{size: size2, root: root2}) do
    :xb5_sets_node.is_equal(size1, root1, size2, root2)
  end

  @spec filter(t(a), (a -> as_boolean(term()))) :: t(a) when a: value()
  def filter(set, fun) do
    from_ordset(for elem <- to_list(set), fun.(elem), do: elem)
  end

  @spec intersection(t(val), t(val)) :: t(val) when val: value()
  def intersection(%__MODULE__{size: size1, root: root1}, %__MODULE__{size: size2, root: root2}) do
    [size | root] = :xb5_sets_node.intersection(size1, root1, size2, root2)
    %__MODULE__{size: size, root: root}
  end

  @doc "Returns the smallest element strictly greater than `element`, or `:error` if none exists."
  @spec larger(t(val), val) :: {:ok, val} | :error when val: value()
  def larger(%__MODULE__{root: root}, element) do
    case :xb5_sets_node.larger(element, root) do
      {:found, e} -> {:ok, e}
      :none -> :error
    end
  end

  @spec largest!(t(val)) :: val when val: value()
  def largest!(%__MODULE__{size: size, root: root}) do
    if size === 0 do
      raise ArgumentError, "set is empty"
    else
      :xb5_sets_node.largest(root)
    end
  end

  @doc """
  Applies `fun` to each element and returns a new set built from the results.

  Because the mapped elements may not be unique, they are deduplicated.
  """
  @spec map(t(a), (a -> b)) :: t(b) when a: value(), b: value()
  def map(%__MODULE__{root: root}, fun) do
    list = :xb5_sets_node.map_to_list(fun, root)
    deduped = :lists.usort(list)
    from_ordset(length(deduped), deduped)
  end

  @spec member?(t(), value()) :: boolean()
  def member?(%__MODULE__{root: root}, value) do
    :xb5_sets_node.is_member(value, root)
  end

  @spec new() :: t()
  def new() do
    %__MODULE__{size: 0, root: :xb5_sets_node.new()}
  end

  @spec new(:xb5_sets.t(val) | Enumerable.t()) :: t(val) when val: value()
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

  @spec new(:xb5_sets.t() | Enumerable.t(), (term() -> val)) :: t(val) when val: value()
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

  @spec pop_largest!(t(val)) :: {val, t(val)} when val: value()
  def pop_largest!(%__MODULE__{size: size, root: root} = set) do
    if size === 0 do
      raise ArgumentError, "set is empty"
    else
      [value | root] = :xb5_sets_node.take_largest(root)
      set = %{set | size: size - 1, root: root}
      {value, set}
    end
  end

  @spec pop_smallest!(t(val)) :: {val, t(val)} when val: value()
  def pop_smallest!(%__MODULE__{size: size, root: root} = set) do
    if size === 0 do
      raise ArgumentError, "set is empty"
    else
      [value | root] = :xb5_sets_node.take_smallest(root)
      set = %{set | size: size - 1, root: root}
      {value, set}
    end
  end

  @spec put(t(val), new_val) :: t(val | new_val) when val: value(), new_val: value()
  def put(%__MODULE__{size: size, root: root} = set, value) do
    case :xb5_sets_node.insert_att(value, root) do
      :key_exists ->
        set

      root ->
        %{set | size: size + 1, root: root}
    end
  end

  @spec reject(t(a), (a -> as_boolean(term()))) :: t(a) when a: value()
  def reject(set, fun) do
    from_ordset(for elem <- to_list(set), !fun.(elem), do: elem)
  end

  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{size: size}) do
    size
  end

  @doc "Returns the largest element strictly less than `element`, or `:error` if none exists."
  @spec smaller(t(val), val) :: {:ok, val} | :error when val: value()
  def smaller(%__MODULE__{root: root}, element) do
    case :xb5_sets_node.smaller(element, root) do
      {:found, e} -> {:ok, e}
      :none -> :error
    end
  end

  @spec smallest!(t(val)) :: val when val: value()
  def smallest!(%__MODULE__{size: size, root: root}) do
    if size === 0 do
      raise ArgumentError, "set is empty"
    else
      :xb5_sets_node.smallest(root)
    end
  end

  @spec split_with(t(), (term() -> as_boolean(term()))) :: {t(), t()}
  def split_with(%__MODULE__{root: root}, fun) do
    root
    |> :xb5_sets_node.to_rev_list()
    |> split_with_recur(fun, 0, [], 0, [])
  end

  @spec subset?(t(), t()) :: boolean()
  def subset?(%__MODULE__{size: size1, root: root1}, %__MODULE__{size: size2, root: root2}) do
    :xb5_sets_node.is_subset(size1, root1, size2, root2)
  end

  @doc """
  Returns elements that are in either set, but not both.

  Implemented as `union(difference(set1, set2), difference(set2, set1))`.
  """
  @spec symmetric_difference(t(val1), t(val2)) :: t(val1 | val2) when val1: value(), val2: value()
  def symmetric_difference(set1, set2) do
    union(difference(set1, set2), difference(set2, set1))
  end

  @spec to_list(t(val)) :: [val] when val: value()
  def to_list(%__MODULE__{root: root}) do
    :xb5_sets_node.to_list(root)
  end

  @spec union(t(val1), t(val2)) :: t(val1 | val2) when val1: value(), val2: value()
  def union(%__MODULE__{size: size1, root: root1}, %__MODULE__{size: size2, root: root2}) do
    [size | root] = :xb5_sets_node.union(size1, root1, size2, root2)
    %__MODULE__{size: size, root: root}
  end

  @doc "Converts the set to a plain map `%{size: n, root: node}` for Erlang interop."
  @spec unwrap(t(val)) :: :xb5_sets.unwrapped_set(val) when val: value()
  def unwrap(%__MODULE__{size: size, root: root}) do
    %{size: size, root: root}
  end

  ## Internal

  defp from_ordset(ordset) do
    size = length(ordset)
    from_ordset(size, ordset)
  end

  defp from_ordset(size, ordset) do
    root = :xb5_sets_node.from_ordset(ordset, size)
    %__MODULE__{size: size, root: root}
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

    def member?(set, val) do
      # NOTE: not strict comparison
      {:ok, Xb5.Set.member?(set, val)}
    end

    def slice(set) do
      size = Xb5.Set.size(set)
      {:ok, size, &Xb5.Set.to_list/1}
    end

    def reduce(set, acc, fun) do
      set
      |> Xb5.Set.to_list()
      |> Enumerable.List.reduce(acc, fun)
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
