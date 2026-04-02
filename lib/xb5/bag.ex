defmodule Xb5.Bag do
  ## Types

  @enforce_keys [:size, :root]
  defstruct [:size, :root]

  @type t(value) :: %__MODULE__{size: non_neg_integer(), root: :xb5_bag_node.t(value)}
  @type t :: t(value)
  @type value :: term

  ## API

  @doc "Returns the number of times `value` appears in the bag."
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

  @doc "Removes one occurrence of `value` from the bag. Returns the bag unchanged if `value` is not present."
  @spec delete(t(val1), val2) :: t(val1) when val1: value(), val2: value()
  def delete(%__MODULE__{size: size, root: root} = set, value) do
    case :xb5_bag_node.delete_att(value, root) do
      :badkey ->
        set

      root ->
        %{set | size: size - 1, root: root}
    end
  end

  @doc "Returns the 0-based index (rank) of `value` in the bag, or `:error` if not present."
  @spec fetch_index(t(value), value) :: {:ok, non_neg_integer} | :error
  def fetch_index(%__MODULE__{root: root}, value) do
    case :xb5_bag_node.rank(value, root) do
      :none ->
        :error

      rank ->
        {:ok, rank - 1}
    end
  end

  @doc "Returns the 0-based index (rank) of `value` in the bag. Raises `KeyError` if not present."
  @spec fetch_index!(t(value), value) :: non_neg_integer
  def fetch_index!(%__MODULE__{root: root} = bag, value) do
    case :xb5_bag_node.rank(value, root) do
      :none ->
        raise KeyError, term: bag, key: value

      rank ->
        rank - 1
    end
  end

  @doc "Returns a new bag containing only elements for which `fun` returns a truthy value."
  @spec filter(t(a), (a -> as_boolean(term()))) :: t(a) when a: value()
  def filter(set, fun) do
    from_ordered_list(for elem <- to_list(set), fun.(elem), do: elem)
  end

  @doc "Returns the 0-based index (rank) of `value` in the bag, or `default` if not present."
  @spec get_index(t(value), value, default) :: non_neg_integer | default when default: term
  def get_index(bag, value, default \\ nil)

  def get_index(%__MODULE__{root: root}, value, default) do
    case :xb5_bag_node.rank(value, root) do
      :none ->
        default

      rank ->
        rank - 1
    end
  end

  @doc "Returns the smallest element strictly greater than `element`, or `:error` if none exists."
  @spec larger(t(val), val) :: {:ok, val} | :error when val: value()
  def larger(%__MODULE__{root: root}, element) do
    case :xb5_bag_node.larger(element, root) do
      {:found, e} -> {:ok, e}
      :none -> :error
    end
  end

  @doc "Returns the largest element in the bag. Raises `ArgumentError` if the bag is empty."
  @spec largest!(t(val)) :: val when val: value()
  def largest!(%__MODULE__{size: size, root: root}) do
    if size === 0 do
      raise ArgumentError, "bag is empty"
    else
      :xb5_bag_node.largest(root)
    end
  end

  @doc "Returns `true` if `value` is present in the bag, `false` otherwise."
  @spec member?(t(), value()) :: boolean()
  def member?(%__MODULE__{root: root}, value) do
    :xb5_bag_node.is_member(value, root)
  end

  @doc "Merges two bags into a new bag containing all elements from both, preserving duplicates."
  @spec merge(t(val1), t(val2)) :: t(val1 | val2) when val1: value(), val2: value()
  def merge(%__MODULE__{size: size1, root: root1}, %__MODULE__{size: size2, root: root2}) do
    size = size1 + size2
    root = :xb5_bag_node.merge(size1, root1, size2, root2)
    %__MODULE__{size: size, root: root}
  end

  @doc "Creates a new empty bag, or builds a bag from an Erlang `xb5_bag` term or an enumerable."
  @spec new() :: t()
  def new() do
    %__MODULE__{size: 0, root: :xb5_bag_node.new()}
  end

  @spec new(:xb5_bag.t(val) | Enumerable.t()) :: t(val) when val: value()
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

  @spec new(:xb5_bag.t() | Enumerable.t(), (term() -> val)) :: t(val) when val: value()
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

  @doc "Returns the percentile value for the given `percentile` (0.0–1.0) using the given method options. Returns `{:value, x}` or `:none`."
  @spec percentile(t(value), percentile, opts) :: {:value, value | interpolation_result} | :none
        when percentile: :xb5_bag_utils.percentile(),
             opts: [:xb5_bag_utils.percentile_bracket_opt()],
             interpolation_result: number

  def percentile(bag, percentile, opts \\ [])

  def percentile(%__MODULE__{size: size, root: root}, percentile, opts) do
    # FIXME review returned value
    value_fun = fn value -> {:value, value} end
    :xb5_bag_utils.percentile(percentile, size, root, value_fun, opts)
  end

  @doc "Returns the percentile bracket for the given `percentile`. Returns `{:exact, x}`, `{:between, low, high}`, or `:none`."
  @spec percentile_bracket(t(value), percentile, opts) :: percentile_bracket
        when percentile: :xb5_bag_utils.percentile(),
             opts: [:xb5_bag_utils.percentile_bracket_opt()],
             percentile_bracket: :xb5_bag_utils.percentile_bracket(value)

  def percentile_bracket(bag, percentile, opts \\ [])

  def percentile_bracket(%__MODULE__{size: size, root: root}, percentile, opts) do
    :xb5_bag_utils.percentile_bracket(percentile, size, root, opts)
  end

  @doc "Returns the percentile rank of `value` in the bag as a float in 0.0–1.0. Raises `ArgumentError` if the bag is empty."
  @spec percentile_rank(t(value), value) :: float
  def percentile_rank(%__MODULE__{size: size, root: root}, value) when size > 0 do
    :xb5_bag_utils.percentile_rank(value, size, root)
  end

  def percentile_rank(%__MODULE__{}, _value) do
    raise ArgumentError, "bag is empty"
  end

  @doc "Removes and returns the largest element. Raises `ArgumentError` if the bag is empty."
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

  @doc "Removes and returns the smallest element. Raises `ArgumentError` if the bag is empty."
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

  @doc "Adds `value` to the bag, always inserting a new copy even if already present."
  @spec push(t(val), new_val) :: t(val | new_val) when val: value(), new_val: value()
  def push(%__MODULE__{size: size, root: root} = set, value) do
    root = :xb5_bag_node.push(value, root)
    %{set | size: size + 1, root: root}
  end

  @doc "Adds `value` to the bag only if it is not already present. Returns the bag unchanged if `value` is present."
  @spec put(t(val), new_val) :: t(val | new_val) when val: value(), new_val: value()
  def put(%__MODULE__{size: size, root: root} = set, value) do
    case :xb5_bag_node.insert_att(value, root) do
      :key_exists ->
        set

      root ->
        %{set | size: size + 1, root: root}
    end
  end

  @doc "Returns a new bag containing only elements for which `fun` returns a falsy value."
  @spec reject(t(a), (a -> as_boolean(term()))) :: t(a) when a: value()
  def reject(set, fun) do
    from_ordered_list(for elem <- to_list(set), !fun.(elem), do: elem)
  end

  @doc "Returns the number of elements in the bag, counting duplicates."
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{size: size}) do
    size
  end

  @doc "Returns the largest element strictly less than `element`, or `:error` if none exists."
  @spec smaller(t(val), val) :: {:ok, val} | :error when val: value()
  def smaller(%__MODULE__{root: root}, element) do
    case :xb5_bag_node.smaller(element, root) do
      {:found, e} -> {:ok, e}
      :none -> :error
    end
  end

  @doc "Returns the smallest element in the bag. Raises `ArgumentError` if the bag is empty."
  @spec smallest!(t(val)) :: val when val: value()
  def smallest!(%__MODULE__{size: size, root: root}) do
    if size === 0 do
      raise ArgumentError, "bag is empty"
    else
      :xb5_bag_node.smallest(root)
    end
  end

  @doc "Returns all elements as a sorted list, with duplicates."
  @spec to_list(t(val)) :: [val] when val: value()
  def to_list(%__MODULE__{root: root}) do
    :xb5_bag_node.to_list(root)
  end

  @doc "Converts the bag to a plain map `%{size: n, root: node}` for Erlang interop."
  @spec unwrap(t(val)) :: :xb5_bag.unwrapped_bag(val) when val: value()
  def unwrap(%__MODULE__{size: size, root: root}) do
    %{size: size, root: root}
  end

  ## Internal

  defp from_ordered_list(list) do
    size = length(list)
    root = :xb5_bag_node.from_ordered_list(list, size)
    %__MODULE__{size: size, root: root}
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
