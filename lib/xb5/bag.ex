defmodule Xb5.Bag do
  ## Types

  @enforce_keys [:size, :root]
  defstruct [:size, :root]

  @type t(value) :: %__MODULE__{size: non_neg_integer(), root: :xb5_bag_node.t(value)}
  @type t :: t(value)
  @type value :: term

  ## API

  # TODO count, rank, etc

  @spec delete(t(val1), val2) :: t(val1) when val1: value(), val2: value()
  def delete(%__MODULE__{size: size, root: root} = set, value) do
    case :xb5_bag_node.delete_att(value, root) do
      :badkey ->
        set

      root ->
        %{set | size: size - 1, root: root}
    end
  end

  @spec filter(t(a), (a -> as_boolean(term()))) :: t(a) when a: value()
  def filter(set, fun) do
    from_ordered_list(for elem <- to_list(set), fun.(elem), do: elem)
  end

  @spec largest!(t(val)) :: val when val: value()
  def largest!(%__MODULE__{size: size, root: root}) do
    if size === 0 do
      raise "Empty Bag"
    else
      :xb5_bag_node.largest(root)
    end
  end

  @spec member?(t(), value()) :: boolean()
  def member?(%__MODULE__{root: root}, value) do
    :xb5_bag_node.is_member(value, root)
  end

  @spec merge(t(val1), t(val2)) :: t(val1 | val2) when val1: value(), val2: value()
  def merge(%__MODULE__{size: size1, root: root1}, %__MODULE__{size: size2, root: root2}) do
    size = size1 + size2
    root = :xb5_bag_node.merge(size1, root1, size2, root2)
    %__MODULE__{size: size, root: root}
  end

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

  @spec pop_largest!(t(val)) :: {val, t(val)} when val: value()
  def pop_largest!(%__MODULE__{size: size, root: root} = set) do
    if size === 0 do
      raise "Empty Bag"
    else
      [value | root] = :xb5_bag_node.take_largest(root)
      set = %{set | size: size - 1, root: root}
      {value, set}
    end
  end

  @spec pop_smallest!(t(val)) :: {val, t(val)} when val: value()
  def pop_smallest!(%__MODULE__{size: size, root: root} = set) do
    if size === 0 do
      raise "Empty Bag"
    else
      [value | root] = :xb5_bag_node.take_smallest(root)
      set = %{set | size: size - 1, root: root}
      {value, set}
    end
  end

  @spec put(t(val), new_val) :: t(val | new_val) when val: value(), new_val: value()
  def put(%__MODULE__{size: size, root: root} = set, value) do
    root = :xb5_bag_node.add(value, root)
    %{set | size: size + 1, root: root}
  end

  @spec put_new(t(val), new_val) :: t(val | new_val) when val: value(), new_val: value()
  def put_new(%__MODULE__{size: size, root: root} = set, value) do
    case :xb5_bag_node.insert_att(value, root) do
      :key_exists ->
        set

      root ->
        %{set | size: size + 1, root: root}
    end
  end

  @spec reject(t(a), (a -> as_boolean(term()))) :: t(a) when a: value()
  def reject(set, fun) do
    from_ordered_list(for elem <- to_list(set), !fun.(elem), do: elem)
  end

  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{size: size}) do
    size
  end

  @spec smallest!(t(val)) :: val when val: value()
  def smallest!(%__MODULE__{size: size, root: root}) do
    if size === 0 do
      raise "Empty Bag"
    else
      :xb5_bag_node.smallest(root)
    end
  end

  @spec to_list(t(val)) :: [val] when val: value()
  def to_list(%__MODULE__{root: root}) do
    :xb5_bag_node.to_list(root)
  end

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

    def slice(bag) do
      size = Xb5.Bag.size(bag)
      # {:ok, size, &slicing_fun(bag, &1, &2, &3)}
      {:ok, size, &Xb5.Bag.to_list/1}
    end

    def reduce(set, acc, fun) do
      set
      |> Xb5.Bag.to_list()
      |> Enumerable.List.reduce(acc, fun)
    end

    ## Internal

    # defp slicing_fun(bag, start, length, step) do
    #  %{root: root} = Xb5.Bag.unwrap(bag)
    #  starting_value = :xb5_bag_node.nth(start + 1, root)
    #  # FIXME doesn't work with duplicate elements, since the iterator may
    #  # start at the wrong position
    #  iterator = :xb5_bag_node.iterator_from(starting_value, root, :ordered)
    #  slice_recur(iterator, length, step, 1)
    # end

    # defp slice_recur(iterator, length, step, substep) when length > 0 do
    #  {value, iterator} = :xb5_bag_node.next(iterator)

    #  cond do
    #    substep === 1 and substep < step ->
    #      [value | slice_recur(iterator, length, step, substep + 1)]

    #    substep === 1 ->
    #      [value | slice_recur(iterator, length - 1, step, 1)]

    #    substep < step ->
    #      slice_recur(iterator, length, step, substep + 1)

    #    substep === step ->
    #      slice_recur(iterator, length - 1, step, 1)
    #  end
    # end

    # defp slice_recur(_iterator, 0, _step, _substep) do
    #  []
    # end
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
