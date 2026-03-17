defmodule Xb5.Tree do
  ## Types

  @enforce_keys [:size, :root]
  defstruct [:size, :root]

  @type t(key, value) :: %__MODULE__{size: non_neg_integer(), root: :xb5_trees_node.t(key, value)}
  @type t :: t(key, value)
  @type key :: term
  @type value :: term

  ## API

  @doc "Removes the entry for `key` from the tree. Returns the tree unchanged if `key` is not present."
  @spec delete(t(), key) :: t()
  def delete(%__MODULE__{size: size, root: root} = tree, key) do
    case :xb5_trees_node.delete_att(key, root) do
      :badkey ->
        tree

      root ->
        %{tree | size: size - 1, root: root}
    end
  end

  @doc "Removes entries for all given `keys`. Keys not present are ignored."
  @spec drop(t(), [key()]) :: t()
  def drop(%__MODULE__{size: size, root: root}, keys) do
    drop_recur(size, root, keys)
  end

  @doc "Returns `true` if both trees contain exactly the same key-value pairs."
  @spec equal?(t(), t()) :: boolean()
  def equal?(%__MODULE__{size: size1, root: root1}, %__MODULE__{size: size2, root: root2}) do
    :xb5_trees_node.is_equal(size1, root1, size2, root2)
  end

  @doc "Returns `{:ok, value}` for `key`, or `:error` if `key` is not present."
  @spec fetch(t(), key()) :: {:ok, value()} | :error
  def fetch(%__MODULE__{root: root}, key) do
    :xb5_trees_node.get_att(key, root, &fetch_found/2, &fetch_not_found/1)
  end

  @doc "Returns the value for `key`. Raises `KeyError` if `key` is not present."
  @spec fetch!(t(), key()) :: value()
  def fetch!(%__MODULE__{root: root}, key) do
    :xb5_trees_node.get_att(key, root, &fetch_bang_found/2, &fetch_bang_not_found/1)
  end

  @doc "Returns a new tree containing only entries for which `fun.({key, value})` returns truthy."
  @spec filter(t(key, value), ({key, value} -> as_boolean(term()))) :: t(key, value)
  def filter(tree, fun) do
    from_orddict(for pair <- to_list(tree), fun.(pair), do: pair)
  end

  @doc "Builds a tree from a list of keys, all mapped to the same `value`."
  @spec from_keys([key()], value()) :: t(key, value)
  def from_keys(keys, value) do
    from_orddict(for key <- keys, do: {key, value})
  end

  @doc "Returns the value for `key`, or `default` if `key` is not present."
  @spec get(t(), key(), value()) :: value()
  def get(tree, key, default \\ nil)

  def get(%__MODULE__{root: root}, key, default) do
    :xb5_trees_node.get_att(key, root, &fetch_bang_found/2, fn _key -> default end)
  end

  @doc "Gets the value for `key` and updates it, following the `Access` behaviour contract."
  @spec get_and_update(
          t(),
          key(),
          (value() | nil -> {current_value, new_value :: value()} | :pop)
        ) ::
          {current_value, new_tree :: t()}
        when current_value: value()
  def get_and_update(%__MODULE__{root: root} = tree, key, fun) do
    case :xb5_trees_node.get_att(key, root, &fetch_found/2, &fetch_not_found/1) do
      {:ok, value} ->
        case fun.(value) do
          {current_value, new_value} ->
            root = :xb5_trees_node.update_att(key, :eager, new_value, root)
            tree = %{tree | root: root}
            {current_value, tree}

          :pop ->
            root = :xb5_trees_node.delete_att(key, root)
            tree = %{tree | size: tree.size - 1, root: root}
            {value, tree}
        end

      :error ->
        value = nil

        case fun.(value) do
          {current_value, new_value} ->
            root = :xb5_trees_node.insert_att(key, :eager, new_value, root)
            tree = %{tree | size: tree.size + 1, root: root}
            {current_value, tree}

          :pop ->
            {value, tree}
        end
    end
  end

  @doc "Gets the value for `key` and updates it, raising `KeyError` if `key` is not present."
  @spec get_and_update!(
          t(),
          key(),
          (value() -> {current_value, new_value :: value()} | :pop)
        ) ::
          {current_value, t()}
        when current_value: value()
  def get_and_update!(%__MODULE__{root: root} = tree, key, fun) do
    value = :xb5_trees_node.get_att(key, root, &fetch_bang_found/2, &fetch_bang_not_found/1)

    case fun.(value) do
      {current_value, new_value} ->
        root = :xb5_trees_node.update_att(key, :eager, new_value, root)
        tree = %{tree | root: root}
        {current_value, tree}

      :pop ->
        root = :xb5_trees_node.delete_att(key, root)
        tree = %{tree | size: tree.size - 1, root: root}
        {value, tree}
    end
  end

  @doc "Returns the value for `key`, or calls `fun.()` to compute a default."
  @spec get_lazy(t(), key(), (-> value())) :: value()
  def get_lazy(%__MODULE__{root: root}, key, fun) do
    :xb5_trees_node.get_att(key, root, &fetch_bang_found/2, fn _key -> fun.() end)
  end

  @doc "Returns `true` if `key` is present in the tree."
  @spec has_key?(t(), key()) :: boolean()
  def has_key?(%__MODULE__{root: root}, key) do
    :xb5_trees_node.get_att(key, root, &has_key_found/2, &has_key_not_found/1)
  end

  @doc "Returns a new tree containing only keys present in both trees. For conflicting keys the right-hand tree's value is kept unless a resolver `fun` is provided."
  @spec intersect(t(), t()) :: t()
  def intersect(%__MODULE__{size: size1, root: root1}, %__MODULE__{size: size2, root: root2}) do
    [size | root] = :xb5_trees_node.intersect(size1, root1, size2, root2)
    %__MODULE__{size: size, root: root}
  end

  @spec intersect(t(), t(), (key(), value(), value() -> value())) :: t()
  def intersect(%__MODULE__{size: size1, root: root1}, %__MODULE__{size: size2, root: root2}, fun) do
    [size | root] = :xb5_trees_node.intersect_with(fun, size1, root1, size2, root2)
    %__MODULE__{size: size, root: root}
  end

  @doc "Returns a sorted list of all keys."
  @spec keys(t()) :: [key()]
  def keys(%__MODULE__{root: root}) do
    :xb5_trees_node.keys(root)
  end

  @doc "Returns the entry with the largest key strictly greater than `key`, or `:error` if none exists."
  @spec larger(t(key, value), key) :: {key, value} | :error
  def larger(%__MODULE__{root: root}, key) do
    case :xb5_trees_node.larger(key, root) do
      {_, _} = found -> found
      :none -> :error
    end
  end

  @doc "Returns the entry with the largest key. Raises `ArgumentError` if the tree is empty."
  @spec largest!(t(key, value)) :: {key, value}
  def largest!(%__MODULE__{size: size, root: root}) do
    if size === 0 do
      raise ArgumentError, "tree is empty"
    else
      :xb5_trees_node.largest(root)
    end
  end

  @doc "Merges two trees. For conflicting keys the right-hand tree's value wins unless a resolver `fun` is provided."
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{size: size1, root: root1}, %__MODULE__{size: size2, root: root2}) do
    [size | root] = :xb5_trees_node.merge(size1, root1, size2, root2)
    %__MODULE__{size: size, root: root}
  end

  @spec merge(t(), t(), (key(), value(), value() -> value())) :: t()
  def merge(%__MODULE__{size: size1, root: root1}, %__MODULE__{size: size2, root: root2}, fun) do
    [size | root] = :xb5_trees_node.merge_with(fun, size1, root1, size2, root2)
    %__MODULE__{size: size, root: root}
  end

  @doc "Creates a new empty tree, or builds a tree from an Erlang `xb5_trees` term or an enumerable of `{key, value}` pairs."
  @spec new() :: t()
  def new() do
    %__MODULE__{size: 0, root: :xb5_trees_node.new()}
  end

  @spec new(:xb5_trees.t(key, value) | Enumerable.t()) :: t(key, value)
  def new(input) do
    case :xb5_trees.unwrap(input) do
      {:ok, %{size: size, root: root}} ->
        %__MODULE__{size: size, root: root}

      {:error, _} ->
        input
        |> Enum.to_list()
        |> from_list()
    end
  end

  @spec new(:xb5_trees.t() | Enumerable.t(), (term() -> value)) :: t(key, value)
  def new(input, transform) do
    case :xb5_trees.unwrap(input) do
      {:ok, %{root: root}} ->
        fn key, value, acc ->
          [transform.({key, value}) | acc]
        end
        |> :xb5_trees_node.foldr([], root)
        |> from_list()

      {:error, _} ->
        input
        |> Enum.map(transform)
        |> from_list()
    end
  end

  @doc "Returns `{value, updated_tree}` for `key`, removing the entry. Returns `{default, tree}` if `key` is not present."
  @spec pop(t(), key(), default) :: {value(), updated_map :: t()} | {default, t()}
        when default: value()
  def pop(tree, key, default \\ nil)

  def pop(%__MODULE__{size: size, root: root} = tree, key, default) do
    case :xb5_trees_node.take_att(key, root) do
      [[_ | value] | root] ->
        tree = %{tree | size: size - 1, root: root}
        {value, tree}

      :badkey ->
        {default, tree}
    end
  end

  @doc "Returns `{value, updated_tree}` for `key`, removing the entry. Raises `KeyError` if `key` is not present."
  @spec pop!(t(), key()) :: {value(), updated_map :: t()}
  def pop!(%__MODULE__{size: size, root: root} = tree, key) do
    case :xb5_trees_node.take_att(key, root) do
      [[_ | value] | root] ->
        tree = %{tree | size: size - 1, root: root}
        {value, tree}

      :badkey ->
        raise KeyError, term: tree, key: key
    end
  end

  @doc "Removes and returns `{key, value, updated_tree}` for the largest key. Raises `ArgumentError` if the tree is empty."
  @spec pop_largest!(t(key, value)) :: {key, value, t(key, value)}
  def pop_largest!(%__MODULE__{size: size, root: root} = tree) do
    if size === 0 do
      raise ArgumentError, "tree is empty"
    else
      [[key | value] | root] = :xb5_trees_node.take_largest(root)
      tree = %{tree | size: size - 1, root: root}
      {key, value, tree}
    end
  end

  @doc "Returns the value for `key`, lazily computing a default from `fun.()` if `key` is not present."
  @spec pop_lazy(t(), key(), (-> value())) :: {value(), t()}
  def pop_lazy(%__MODULE__{size: size, root: root} = tree, key, fun) do
    case :xb5_trees_node.take_att(key, root) do
      [[_ | value] | root] ->
        tree = %{tree | size: size - 1, root: root}
        {value, tree}

      :badkey ->
        value = fun.()
        {value, tree}
    end
  end

  @doc "Removes and returns `{key, value, updated_tree}` for the smallest key. Raises `ArgumentError` if the tree is empty."
  @spec pop_smallest!(t(key, value)) :: {key, value, t(key, value)}
  def pop_smallest!(%__MODULE__{size: size, root: root} = tree) do
    if size === 0 do
      raise ArgumentError, "tree is empty"
    else
      [[key | value] | root] = :xb5_trees_node.take_smallest(root)
      tree = %{tree | size: size - 1, root: root}
      {key, value, tree}
    end
  end

  @doc "Inserts or updates `key` with `value`. If `key` already exists its value is replaced."
  @spec put(t(), key(), value()) :: t()
  def put(%__MODULE__{size: size, root: root} = tree, key, value) do
    case :xb5_trees_node.insert_att(key, :eager, value, root) do
      :key_exists ->
        root = :xb5_trees_node.update_att(key, :eager, value, root)
        %{tree | root: root}

      root ->
        %{tree | size: size + 1, root: root}
    end
  end

  @doc "Inserts `key` with `value` only if `key` is not already present."
  @spec put_new(t(), key(), value()) :: t()
  def put_new(%__MODULE__{size: size, root: root} = tree, key, value) do
    case :xb5_trees_node.insert_att(key, :eager, value, root) do
      :key_exists ->
        tree

      root ->
        %{tree | size: size + 1, root: root}
    end
  end

  @doc "Inserts `key` only if not already present, using `fun.()` to compute the value lazily."
  @spec put_new_lazy(t(), key(), (-> value())) :: t()
  def put_new_lazy(%__MODULE__{size: size, root: root} = tree, key, fun) do
    case :xb5_trees_node.insert_att(key, :lazy, fun, root) do
      :key_exists ->
        tree

      root ->
        %{tree | size: size + 1, root: root}
    end
  end

  @doc "Returns a new tree containing only entries for which `fun.({key, value})` returns falsy."
  @spec reject(t(key, value), ({key, value} -> as_boolean(term()))) :: t(key, value)
  def reject(tree, fun) do
    from_orddict(for pair <- to_list(tree), !fun.(pair), do: pair)
  end

  @doc "Updates the value for `key` if present; returns the tree unchanged if `key` is not present."
  @spec replace(t(), key(), value()) :: t()
  def replace(%__MODULE__{root: root} = tree, key, value) do
    case :xb5_trees_node.update_att(key, :eager, value, root) do
      :badkey ->
        tree

      root ->
        %{tree | root: root}
    end
  end

  @doc "Updates the value for `key`. Raises `KeyError` if `key` is not present."
  @spec replace!(t(), key(), value()) :: t()
  def replace!(%__MODULE__{root: root} = tree, key, value) do
    case :xb5_trees_node.update_att(key, :eager, value, root) do
      :badkey ->
        raise KeyError, term: tree, key: key

      root ->
        %{tree | root: root}
    end
  end

  @doc "Updates the value for `key` lazily if present; returns the tree unchanged if `key` is not present."
  @spec replace_lazy(t(), key(), (existing_value :: value() -> new_value :: value())) ::
          t()
  def replace_lazy(%__MODULE__{root: root} = tree, key, fun) do
    case :xb5_trees_node.update_att(key, :lazy, fun, root) do
      :badkey ->
        tree

      root ->
        %{tree | root: root}
    end
  end

  @doc "Returns the number of entries in the tree."
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{size: size}) do
    size
  end

  @doc "Returns the entry with the largest key strictly less than `key`, or `:error` if none exists."
  @spec smaller(t(key, value), value) :: {key, value} | :error
  def smaller(%__MODULE__{root: root}, element) do
    case :xb5_trees_node.smaller(element, root) do
      {_, _} = found -> found
      :none -> :error
    end
  end

  @doc "Returns the entry with the smallest key. Raises `ArgumentError` if the tree is empty."
  @spec smallest!(t(key, value)) :: {key, value}
  def smallest!(%__MODULE__{size: size, root: root}) do
    if size === 0 do
      raise ArgumentError, "tree is empty"
    else
      :xb5_trees_node.smallest(root)
    end
  end

  @doc "Splits the tree into two: `{tree_with_given_keys, tree_without_given_keys}`."
  @spec split(t(), [key()]) :: {t(), t()}
  def split(%__MODULE__{root: root}, keys) do
    rev_keys = keys |> :lists.usort() |> :lists.reverse()

    root
    |> :xb5_trees_node.to_rev_list()
    |> split_recur(rev_keys, 0, [], 0, [])
  end

  @doc "Splits the tree into `{tree_where_fun_is_truthy, tree_where_fun_is_falsy}`."
  @spec split_with(t(), ({key(), value()} -> as_boolean(term()))) :: {t(), t()}
  def split_with(%__MODULE__{root: root}, fun) do
    root
    |> :xb5_trees_node.to_rev_list()
    |> split_with_recur(fun, 0, [], 0, [])
  end

  @doc "Returns a new tree containing only the entries for the given `keys`."
  @spec take(t(), [key()]) :: t()
  def take(%__MODULE__{root: root}, keys) do
    keys
    |> :lists.usort()
    |> Enum.map(fn key ->
      :xb5_trees_node.get_att(key, root, &take_get_found/2, &take_get_not_found/1)
    end)
    |> Enum.filter(&(&1 !== nil))
    |> from_orddict()
  end

  @doc "Returns all entries as a key-sorted list of `{key, value}` pairs."
  @spec to_list(t(key, value)) :: [value]
  def to_list(%__MODULE__{root: root}) do
    :xb5_trees_node.to_list(root)
  end

  @doc "Updates the value for `key` by applying `fun` to the current value; inserts with `default` if `key` is not present."
  @spec update(
          t(),
          key(),
          default :: value(),
          (existing_value :: value() -> new_value :: value())
        ) ::
          t()
  def update(%__MODULE__{root: root, size: size} = tree, key, default, fun) do
    case :xb5_trees_node.update_att(key, :lazy, fun, root) do
      :badkey ->
        root = :xb5_trees_node.insert_att(key, :eager, default, root)
        %{tree | size: size + 1, root: root}

      root ->
        %{tree | root: root}
    end
  end

  @doc "Updates the value for `key` by applying `fun`. Raises `KeyError` if `key` is not present."
  @spec update!(t(), key(), (existing_value :: value() -> new_value :: value())) ::
          t()
  def update!(%__MODULE__{root: root} = tree, key, fun) do
    case :xb5_trees_node.update_att(key, :lazy, fun, root) do
      :badkey ->
        raise KeyError, term: tree, key: key

      root ->
        %{tree | root: root}
    end
  end

  @doc "Returns a sorted list of all values (in key order)."
  @spec values(t()) :: [value()]
  def values(%__MODULE__{root: root}) do
    :xb5_trees_node.values(root)
  end

  @doc "Converts the tree to a plain map `%{size: n, root: node}` for Erlang interop."
  @spec unwrap(t(key, value)) :: :xb5_trees.unwrapped_tree(key, value)
  def unwrap(%__MODULE__{size: size, root: root}) do
    %{size: size, root: root}
  end

  @doc "Applies `fun.(key, value)` to every entry, returning a new tree with updated values. Size unchanged."
  @spec map(t(key, value), (key, value -> new_value)) :: t(key, new_value)
        when new_value: value()
  def map(%__MODULE__{root: root} = tree, fun) do
    root = :xb5_trees_node.map(fn k, v -> fun.(k, v) end, root)
    %{tree | root: root}
  end

  ## Internal

  defp from_list(list) do
    # We reverse the list so that the last occurrences of repeated keys are kept.
    rev_list = :lists.reverse(list)
    sorted_list = :lists.ukeysort(1, rev_list)
    from_orddict(sorted_list)
  end

  defp from_orddict(orddict) do
    size = length(orddict)
    from_orddict(size, orddict)
  end

  defp from_orddict(size, orddict) do
    root = :xb5_trees_node.from_orddict(orddict, size)
    %__MODULE__{size: size, root: root}
  end

  ##

  defp drop_recur(size, root, [key | next]) do
    case :xb5_trees_node.delete_att(key, root) do
      :badkey ->
        drop_recur(size, root, next)

      root ->
        drop_recur(size - 1, root, next)
    end
  end

  defp drop_recur(size, root, []) do
    %__MODULE__{size: size, root: root}
  end

  ##

  defp fetch_bang_found(_key, value), do: value
  defp fetch_bang_not_found(key), do: raise(KeyError, key: key)

  ##

  def fetch_found(_key, value), do: {:ok, value}
  def fetch_not_found(_key), do: :error

  ##

  def has_key_found(_key, _value), do: true
  def has_key_not_found(_key), do: false

  ##

  defp split_recur([{key, _} = pair | next] = list, cmp_keys, size1, acc1, size2, acc2) do
    case cmp_keys do
      [cmp_key | _] when cmp_key < key ->
        size2 = size2 + 1
        acc2 = [pair | acc2]
        split_recur(next, cmp_keys, size1, acc1, size2, acc2)

      [cmp_key | next_cmp_keys] when cmp_key > key ->
        size2 = size2 + 1
        acc2 = [pair | acc2]
        split_recur(next, next_cmp_keys, size1, acc1, size2, acc2)

      [_ | next_cmp_keys] ->
        size1 = size1 + 1
        acc1 = [pair | acc1]
        split_recur(next, next_cmp_keys, size1, acc1, size2, acc2)

      [] ->
        size2 = size2 + length(acc2)
        acc2 = :lists.reverse(list, acc2)
        split_finish(size1, acc1, size2, acc2)
    end
  end

  defp split_recur([], _cmp_keys, size1, acc1, size2, acc2) do
    split_finish(size1, acc1, size2, acc2)
  end

  defp split_finish(size1, acc1, size2, acc2) do
    tree1 = from_orddict(size1, acc1)
    tree2 = from_orddict(size2, acc2)
    {tree1, tree2}
  end

  ##

  defp split_with_recur([pair | next], fun, size1, acc1, size2, acc2) do
    if fun.(pair) do
      size1 = size1 + 1
      acc1 = [pair | acc1]
      split_with_recur(next, fun, size1, acc1, size2, acc2)
    else
      size2 = size2 + 1
      acc2 = [pair | acc2]
      split_with_recur(next, fun, size1, acc1, size2, acc2)
    end
  end

  defp split_with_recur([], _fun, size1, acc1, size2, acc2) do
    split_finish(size1, acc1, size2, acc2)
  end

  ##

  defp take_get_found(key, value), do: {key, value}
  defp take_get_not_found(_key), do: nil

  ## Protocols - Enumerable

  defimpl Enumerable do
    def count(tree) do
      {:ok, Xb5.Tree.size(tree)}
    end

    def member?(%Xb5.Tree{root: root}, {key, value}) do
      result =
        :xb5_trees_node.get_att(
          key,
          root,
          &member_get_found(&1, &2, key, value),
          &member_get_not_found/1
        )

      {:ok, result}
    end

    def member?(_tree, _other) do
      {:ok, false}
    end

    def slice(tree) do
      size = Xb5.Tree.size(tree)
      {:ok, size, &Xb5.Tree.to_list/1}
    end

    def reduce(tree, acc, fun) do
      tree
      |> Xb5.Tree.to_list()
      |> Enumerable.List.reduce(acc, fun)
    end

    ##

    defp member_get_found(tree_key, tree_value, queried_key, queried_value) do
      # FIXME is this consistent with non-strict comparisons elsewhere?
      tree_key === queried_key and tree_value === queried_value
    end

    defp member_get_not_found(_key) do
      false
    end
  end

  ## Protocols - Collectable

  defimpl Collectable do
    def into(%@for{} = tree) do
      fun = fn
        tree, {:cont, {key, value}} -> Xb5.Tree.put(tree, key, value)
        tree, :done -> tree
        _, :halt -> :ok
      end

      {tree, fun}
    end
  end

  ## Protocols - Inspect

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(tree, %Inspect.Opts{} = opts) do
      {doc, %{limit: limit}} =
        tree
        |> Xb5.Tree.to_list()
        |> to_doc_with_opts(%{opts | charlists: :as_lists})

      # FIXME improve formatting
      {concat(["Xb5.Tree.new(", doc, ")"]), %{opts | limit: limit}}
    end
  end
end
