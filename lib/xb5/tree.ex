defmodule Xb5.Tree do
  @moduledoc """
  An ordered key-value store backed by a [B-tree](https://en.wikipedia.org/wiki/B-tree) of order 5.

  Keys are kept in ascending Erlang term order. Comparisons use `==` rather than `===` —
  so key `1` and key `1.0` are treated as the same key, unlike `Map`.

  ## Comparison with `Map`

  `Xb5.Tree` supports the same operations as `Map` — `get/3`, `put/3`, `delete/2`,
  `update/4`, `merge/2`, and so on — and additionally offers O(log n) access to ordered
  extremes and neighbors:

    * `largest!/1`, `smallest!/1` — retrieve the entry with the max/min key.
    * `larger/2`, `smaller/2` — find the nearest entry above or below a given key.
    * `pop_largest!/1`, `pop_smallest!/1` — remove and return endpoint entries.

  Conversion to a sorted list of `{key, value}` pairs via `to_list/1` always yields
  entries in ascending key order.

  ## Erlang interop

  `Xb5.Tree` is compatible with the Erlang `:xb5_trees` module. Build one from an
  `:xb5_trees` term via `new/1`. To go the other way, call `unwrap/1` to extract the
  size and root node, then pass the result to `:xb5_trees.wrap/1`.

  ## Examples

      iex> tree = Xb5.Tree.new([b: 2, a: 1])
      Xb5.Tree.new([a: 1, b: 2])

      iex> Xb5.Tree.get(tree, :a)
      1

      iex> Xb5.Tree.largest!(tree)
      {:b, 2}

  """

  ## Types

  @enforce_keys [:size, :root]
  defstruct [:size, :root]

  @type t(key, value) :: %__MODULE__{size: non_neg_integer(), root: :xb5_trees_node.t(key, value)}
  @type t :: t(key, value)
  @type key :: term
  @type value :: term

  ## API

  @doc """
  Deletes the entry in `tree` for a specific `key`.

  If `key` does not exist, returns `tree` unchanged.

  ## Examples

      iex> Xb5.Tree.delete(Xb5.Tree.new([a: 1, b: 2]), :a)
      Xb5.Tree.new([b: 2])
      iex> Xb5.Tree.delete(Xb5.Tree.new([b: 2]), :a)
      Xb5.Tree.new([b: 2])

  """
  @spec delete(t(), key) :: t()
  def delete(%__MODULE__{size: size, root: root} = tree, key) do
    case :xb5_trees_node.delete_att(key, root) do
      :badkey ->
        tree

      root ->
        %{tree | size: size - 1, root: root}
    end
  end

  @doc """
  Drops the given `keys` from `tree`.

  If `keys` contains keys that are not in `tree`, they're simply ignored.

  ## Examples

      iex> Xb5.Tree.drop(Xb5.Tree.new([a: 1, b: 2, c: 3]), [:b, :d])
      Xb5.Tree.new([a: 1, c: 3])

  """
  @spec drop(t(), [key()]) :: t()
  def drop(%__MODULE__{size: size, root: root}, keys) do
    drop_recur(size, root, keys)
  end

  @doc """
  Checks if two trees are equal.

  Two trees are considered equal if they contain the same keys and those keys contain
  the same values. Keys are compared using `==`, so key `1` and key `1.0` are treated
  as identical. Values are compared using `===`, so a value of `1` does not equal `1.0`.

  ## Examples

      iex> Xb5.Tree.equal?(Xb5.Tree.new([a: 1, b: 2]), Xb5.Tree.new([b: 2, a: 1]))
      true
      iex> Xb5.Tree.equal?(Xb5.Tree.new([a: 1, b: 2]), Xb5.Tree.new([b: 1, a: 2]))
      false
      iex> Xb5.Tree.equal?(Xb5.Tree.new([{1, :x}]), Xb5.Tree.new([{1.0, :x}]))
      true
      iex> Xb5.Tree.equal?(Xb5.Tree.new([a: 1.0]), Xb5.Tree.new([a: 1]))
      false

  """
  @spec equal?(t(), t()) :: boolean()
  def equal?(%__MODULE__{size: size1, root: root1}, %__MODULE__{size: size2, root: root2}) do
    :xb5_trees_node.is_equal(size1, root1, size2, root2)
  end

  @doc """
  Fetches the value for a specific `key` in the given `tree`.

  If `tree` contains the given `key` then its value is returned in the shape of `{:ok, value}`.
  If `tree` doesn't contain `key`, `:error` is returned.

  ## Examples

      iex> Xb5.Tree.fetch(Xb5.Tree.new([a: 1]), :a)
      {:ok, 1}
      iex> Xb5.Tree.fetch(Xb5.Tree.new([a: 1]), :b)
      :error

  """
  @spec fetch(t(), key()) :: {:ok, value()} | :error
  def fetch(%__MODULE__{root: root}, key) do
    :xb5_trees_node.get_att(key, root, &fetch_found/2, &fetch_not_found/1)
  end

  @doc """
  Fetches the value for a specific `key` in the given `tree`, erroring out if `tree`
  doesn't contain `key`.

  If `tree` contains `key`, the corresponding value is returned. If `tree` doesn't
  contain `key`, a `KeyError` exception is raised.

  ## Examples

      iex> Xb5.Tree.fetch!(Xb5.Tree.new([a: 1]), :a)
      1
      iex> Xb5.Tree.fetch!(Xb5.Tree.new([a: 1]), :b)
      ** (KeyError) key :b not found

  """
  @spec fetch!(t(), key()) :: value()
  def fetch!(%__MODULE__{root: root} = tree, key) do
    :xb5_trees_node.get_att(key, root, &fetch_bang_found/2, &fetch_bang_not_found(tree, &1))
  end

  @doc """
  Returns a new tree containing only entries from `tree` for which `fun` returns a truthy value.

  `fun` receives each `{key, value}` pair as its only argument.

  See also `reject/2` which discards all entries where the function returns a truthy value.

  ## Examples

      iex> Xb5.Tree.filter(Xb5.Tree.new([one: 1, two: 2, three: 3]), fn {_key, val} -> rem(val, 2) == 1 end)
      Xb5.Tree.new([one: 1, three: 3])

  """
  @spec filter(t(key, value), ({key, value} -> as_boolean(term()))) :: t(key, value)
  def filter(tree, fun) do
    from_orddict(for pair <- to_list(tree), fun.(pair), do: pair)
  end

  @doc """
  Builds a tree from the given `keys` and the fixed `value`.

  ## Examples

      iex> Xb5.Tree.from_keys([:a, :b, :c], 0)
      Xb5.Tree.new([a: 0, b: 0, c: 0])

  """
  @spec from_keys(Enumerable.t(key()), value()) :: t(key, value)
  def from_keys(keys, value) do
    unique_keys_list =
      keys
      |> Enum.to_list()
      |> :lists.usort()

    from_orddict(for key <- unique_keys_list, do: {key, value})
  end

  @doc """
  Gets the value for a specific `key` in `tree`.

  If `key` is present in `tree` then its value is returned. Otherwise, `default` is returned.

  If `default` is not provided, `nil` is used.

  ## Examples

      iex> Xb5.Tree.get(Xb5.Tree.new(), :a)
      nil
      iex> Xb5.Tree.get(Xb5.Tree.new([a: 1]), :a)
      1
      iex> Xb5.Tree.get(Xb5.Tree.new([a: 1]), :b)
      nil
      iex> Xb5.Tree.get(Xb5.Tree.new([a: 1]), :b, 3)
      3
      iex> Xb5.Tree.get(Xb5.Tree.new([a: nil]), :a, 1)
      nil

  """
  @spec get(t(), key(), value()) :: value()
  def get(tree, key, default \\ nil)

  def get(%__MODULE__{root: root}, key, default) do
    :xb5_trees_node.get_att(key, root, &fetch_bang_found/2, fn _key -> default end)
  end

  @doc """
  Gets the value from `key` and updates it, all in one pass.

  `fun` is called with the current value under `key` in `tree` (or `nil` if `key` is not
  present in `tree`) and must return a two-element tuple: the current value (the retrieved
  value, which can be operated on before being returned) and the new value to be stored
  under `key` in the resulting new tree. `fun` may also return `:pop`, which means the
  current value shall be removed from `tree` and returned.

  The returned value is a two-element tuple with the current value returned by `fun` and a
  new tree with the updated value under `key`.

  ## Examples

      iex> Xb5.Tree.get_and_update(Xb5.Tree.new([a: 1]), :a, fn current_value ->
      ...>   {current_value, "new value!"}
      ...> end)
      {1, Xb5.Tree.new([a: "new value!"])}

      iex> Xb5.Tree.get_and_update(Xb5.Tree.new([a: 1]), :b, fn current_value ->
      ...>   {current_value, "new value!"}
      ...> end)
      {nil, Xb5.Tree.new([a: 1, b: "new value!"])}

      iex> Xb5.Tree.get_and_update(Xb5.Tree.new([a: 1]), :a, fn _ -> :pop end)
      {1, Xb5.Tree.new([])}

      iex> Xb5.Tree.get_and_update(Xb5.Tree.new([a: 1]), :b, fn _ -> :pop end)
      {nil, Xb5.Tree.new([a: 1])}

  """
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

  @doc """
  Gets the value from `key` and updates it, all in one pass. Raises if there is no `key`.

  Behaves exactly like `get_and_update/3`, but raises a `KeyError` exception if `key` is
  not present in `tree`.

  ## Examples

      iex> Xb5.Tree.get_and_update!(Xb5.Tree.new([a: 1]), :a, fn current_value ->
      ...>   {current_value, "new value!"}
      ...> end)
      {1, Xb5.Tree.new([a: "new value!"])}

      iex> Xb5.Tree.get_and_update!(Xb5.Tree.new([a: 1]), :b, fn current_value ->
      ...>   {current_value, "new value!"}
      ...> end)
      ** (KeyError) key :b not found

      iex> Xb5.Tree.get_and_update!(Xb5.Tree.new([a: 1]), :a, fn _ ->
      ...>   :pop
      ...> end)
      {1, Xb5.Tree.new([])}

  """
  @spec get_and_update!(
          t(),
          key(),
          (value() -> {current_value, new_value :: value()} | :pop)
        ) ::
          {current_value, t()}
        when current_value: value()
  def get_and_update!(%__MODULE__{root: root} = tree, key, fun) do
    value =
      :xb5_trees_node.get_att(key, root, &fetch_bang_found/2, &fetch_bang_not_found(tree, &1))

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

  @doc """
  Gets the value for a specific `key` in `tree`.

  If `key` is present in `tree` then its value is returned. Otherwise, `fun` is evaluated
  and its result is returned.

  This is useful if the default value is very expensive to calculate or generally difficult
  to setup and teardown again.

  ## Examples

      iex> tree = Xb5.Tree.new([a: 1])
      iex> fun = fn ->
      ...>   # some expensive operation here
      ...>   13
      ...> end
      iex> Xb5.Tree.get_lazy(tree, :a, fun)
      1
      iex> Xb5.Tree.get_lazy(tree, :b, fun)
      13

  """
  @spec get_lazy(t(), key(), (-> value())) :: value()
  def get_lazy(%__MODULE__{root: root}, key, fun) do
    :xb5_trees_node.get_att(key, root, &fetch_bang_found/2, fn _key -> fun.() end)
  end

  @doc """
  Returns whether the given `key` exists in the given `tree`.

  ## Examples

      iex> Xb5.Tree.has_key?(Xb5.Tree.new([a: 1]), :a)
      true
      iex> Xb5.Tree.has_key?(Xb5.Tree.new([a: 1]), :b)
      false

  """
  @spec has_key?(t(), key()) :: boolean()
  def has_key?(%__MODULE__{root: root}, key) do
    :xb5_trees_node.get_att(key, root, &has_key_found/2, &has_key_not_found/1)
  end

  @doc """
  Intersects two trees, returning a tree with the common keys.

  The values in the returned tree are the values of the intersected keys in `tree2`.

  ## Examples

      iex> Xb5.Tree.intersect(Xb5.Tree.new([a: 1, b: 2]), Xb5.Tree.new([b: "b", c: "c"]))
      Xb5.Tree.new([b: "b"])

  """
  @spec intersect(t(), t()) :: t()
  def intersect(%__MODULE__{size: size1, root: root1}, %__MODULE__{size: size2, root: root2}) do
    [size | root] = :xb5_trees_node.intersect(size1, root1, size2, root2)
    %__MODULE__{size: size, root: root}
  end

  @doc """
  Intersects two trees, returning a tree with the common keys and resolving conflicts through
  a function.

  The given function will be invoked when there are duplicate keys; its arguments are `key`
  (the duplicate key), `value1` (the value of `key` in `tree1`), and `value2` (the value of
  `key` in `tree2`). The value returned by `fun` is used as the value under `key` in the
  resulting tree.

  ## Examples

      iex> Xb5.Tree.intersect(Xb5.Tree.new([a: 1, b: 2]), Xb5.Tree.new([b: 2, c: 3]), fn _k, v1, v2 ->
      ...>   v1 + v2
      ...> end)
      Xb5.Tree.new([b: 4])

  """
  @spec intersect(t(), t(), (key(), value(), value() -> value())) :: t()
  def intersect(%__MODULE__{size: size1, root: root1}, %__MODULE__{size: size2, root: root2}, fun) do
    [size | root] = :xb5_trees_node.intersect_with(fun, size1, root1, size2, root2)
    %__MODULE__{size: size, root: root}
  end

  @doc """
  Returns all keys from `tree` in ascending order.

  ## Examples

      iex> Xb5.Tree.keys(Xb5.Tree.new([a: 1, b: 2]))
      [:a, :b]

  """
  @spec keys(t()) :: [key()]
  def keys(%__MODULE__{root: root}) do
    :xb5_trees_node.keys(root)
  end

  @doc """
  Returns the entry immediately following `key` in `tree`.

  If `tree` contains an entry with a key strictly greater than `key`, it is returned as
  `{next_key, value}`. Otherwise returns `:error`.

  ## Examples

      iex> Xb5.Tree.larger(Xb5.Tree.new([a: 1, b: 2, c: 3]), :b)
      {:c, 3}
      iex> Xb5.Tree.larger(Xb5.Tree.new([a: 1, b: 2, c: 3]), :c)
      :error

  """
  @spec larger(t(key, value), key) :: {key, value} | :error
  def larger(%__MODULE__{root: root}, key) do
    case :xb5_trees_node.larger(key, root) do
      {_, _} = found -> found
      :none -> :error
    end
  end

  @doc """
  Returns the entry with the largest key in `tree`.

  Raises `ArgumentError` if `tree` is empty.

  ## Examples

      iex> Xb5.Tree.largest!(Xb5.Tree.new([a: 1, b: 2, c: 3]))
      {:c, 3}
      iex> Xb5.Tree.largest!(Xb5.Tree.new([]))
      ** (ArgumentError) tree is empty

  """
  @spec largest!(t(key, value)) :: {key, value}
  def largest!(%__MODULE__{size: size, root: root}) do
    if size === 0 do
      raise ArgumentError, "tree is empty"
    else
      :xb5_trees_node.largest(root)
    end
  end

  @doc """
  Returns a new tree with all values replaced according to `fun`.

  `fun` receives the key and value of each entry and must return the new value.

  ## Examples

      iex> Xb5.Tree.map(Xb5.Tree.new([a: 1, b: 2]), fn _k, v -> v * 2 end)
      Xb5.Tree.new([a: 2, b: 4])

  """
  @spec map(t(key, value), (key, value -> new_value)) :: t(key, new_value)
        when new_value: value()
  def map(%__MODULE__{root: root} = tree, fun) do
    root = :xb5_trees_node.map(fn k, v -> fun.(k, v) end, root)
    %{tree | root: root}
  end

  @doc """
  Merges two trees into one.

  All keys in `tree2` will be added to `tree1`, overriding any existing value
  (i.e. the keys in `tree2` have precedence over the ones in `tree1`).

  ## Examples

      iex> Xb5.Tree.merge(Xb5.Tree.new([a: 1, b: 2]), Xb5.Tree.new([a: 3, d: 4]))
      Xb5.Tree.new([a: 3, b: 2, d: 4])

  """
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{size: size1, root: root1}, %__MODULE__{size: size2, root: root2}) do
    [size | root] = :xb5_trees_node.merge(size1, root1, size2, root2)
    %__MODULE__{size: size, root: root}
  end

  @doc """
  Merges two trees into one, resolving conflicts through the given `fun`.

  All keys in `tree2` will be added to `tree1`. The given function will be invoked when
  there are duplicate keys; its arguments are `key` (the duplicate key), `value1` (the
  value of `key` in `tree1`), and `value2` (the value of `key` in `tree2`). The value
  returned by `fun` is used as the value under `key` in the resulting tree.

  ## Examples

      iex> Xb5.Tree.merge(Xb5.Tree.new([a: 1, b: 2]), Xb5.Tree.new([a: 3, d: 4]), fn _k, v1, v2 ->
      ...>   v1 + v2
      ...> end)
      Xb5.Tree.new([a: 4, b: 2, d: 4])

  """
  @spec merge(t(), t(), (key(), value(), value() -> value())) :: t()
  def merge(%__MODULE__{size: size1, root: root1}, %__MODULE__{size: size2, root: root2}, fun) do
    [size | root] = :xb5_trees_node.merge_with(fun, size1, root1, size2, root2)
    %__MODULE__{size: size, root: root}
  end

  @doc """
  Returns a new empty tree.

  ## Examples

      iex> Xb5.Tree.new()
      Xb5.Tree.new([])

  """
  @spec new() :: t()
  def new() do
    %__MODULE__{size: 0, root: :xb5_trees_node.new()}
  end

  @doc """
  Creates a tree from an Erlang `:xb5_trees` term or an enumerable of `{key, value}` pairs.

  Duplicated keys are removed; the latest one prevails. When given an Erlang `:xb5_trees`
  term, the underlying structure is reused directly.

  ## Examples

      iex> Xb5.Tree.new([{:b, 1}, {:a, 2}])
      Xb5.Tree.new([a: 2, b: 1])
      iex> Xb5.Tree.new(a: 1, a: 2, a: 3)
      Xb5.Tree.new([a: 3])

  """
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

  @doc """
  Creates a tree from an Erlang `:xb5_trees` term or an enumerable via the transformation
  function.

  `transform` receives each element and must return a `{key, value}` pair. Duplicated keys
  are removed; the latest one prevails.

  ## Examples

      iex> Xb5.Tree.new([:a, :b], fn x -> {x, x} end)
      Xb5.Tree.new([a: :a, b: :b])

  """
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

  @doc """
  Removes the value associated with `key` in `tree` and returns the value and the updated tree.

  If `key` is present in `tree`, it returns `{value, updated_tree}` where `value` is the value
  of the key and `updated_tree` is the result of removing `key` from `tree`. If `key` is not
  present in `tree`, `{default, tree}` is returned.

  ## Examples

      iex> Xb5.Tree.pop(Xb5.Tree.new([a: 1]), :a)
      {1, Xb5.Tree.new([])}
      iex> Xb5.Tree.pop(Xb5.Tree.new([a: 1]), :b)
      {nil, Xb5.Tree.new([a: 1])}
      iex> Xb5.Tree.pop(Xb5.Tree.new([a: 1]), :b, 3)
      {3, Xb5.Tree.new([a: 1])}

  """
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

  @doc """
  Removes and returns the value associated with `key` in `tree` alongside the updated tree,
  or raises if `key` is not present.

  Behaves the same as `pop/3` but raises a `KeyError` exception if `key` is not present
  in `tree`.

  ## Examples

      iex> Xb5.Tree.pop!(Xb5.Tree.new([a: 1]), :a)
      {1, Xb5.Tree.new([])}
      iex> Xb5.Tree.pop!(Xb5.Tree.new([a: 1, b: 2]), :a)
      {1, Xb5.Tree.new([b: 2])}
      iex> Xb5.Tree.pop!(Xb5.Tree.new([a: 1]), :b)
      ** (KeyError) key :b not found in:
      ...

  """
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

  @doc """
  Removes and returns `{key, value, updated_tree}` for the entry with the largest key.

  Raises `ArgumentError` if `tree` is empty.

  ## Examples

      iex> Xb5.Tree.pop_largest!(Xb5.Tree.new([a: 1, b: 2, c: 3]))
      {:c, 3, Xb5.Tree.new([a: 1, b: 2])}
      iex> Xb5.Tree.pop_largest!(Xb5.Tree.new([]))
      ** (ArgumentError) tree is empty

  """
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

  @doc """
  Lazily returns and removes the value associated with `key` in `tree`.

  If `key` is present in `tree`, it returns `{value, updated_tree}` where `value` is the
  value of the key and `updated_tree` is the result of removing `key` from `tree`. If `key`
  is not present in `tree`, `{fun_result, tree}` is returned, where `fun_result` is the
  result of applying `fun`.

  This is useful if the default value is very expensive to calculate or generally difficult
  to setup and teardown again.

  ## Examples

      iex> tree = Xb5.Tree.new([a: 1])
      iex> fun = fn ->
      ...>   # some expensive operation here
      ...>   13
      ...> end
      iex> Xb5.Tree.pop_lazy(tree, :a, fun)
      {1, Xb5.Tree.new([])}
      iex> Xb5.Tree.pop_lazy(tree, :b, fun)
      {13, Xb5.Tree.new([a: 1])}

  """
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

  @doc """
  Removes and returns `{key, value, updated_tree}` for the entry with the smallest key.

  Raises `ArgumentError` if `tree` is empty.

  ## Examples

      iex> Xb5.Tree.pop_smallest!(Xb5.Tree.new([a: 1, b: 2, c: 3]))
      {:a, 1, Xb5.Tree.new([b: 2, c: 3])}
      iex> Xb5.Tree.pop_smallest!(Xb5.Tree.new([]))
      ** (ArgumentError) tree is empty

  """
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

  @doc """
  Puts the given `value` under `key` in `tree`.

  If `key` already exists, its value is replaced.

  ## Examples

      iex> Xb5.Tree.put(Xb5.Tree.new([a: 1]), :b, 2)
      Xb5.Tree.new([a: 1, b: 2])
      iex> Xb5.Tree.put(Xb5.Tree.new([a: 1, b: 2]), :a, 3)
      Xb5.Tree.new([a: 3, b: 2])

  """
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

  @doc """
  Puts the given `value` under `key` unless the entry `key` already exists in `tree`.

  ## Examples

      iex> Xb5.Tree.put_new(Xb5.Tree.new([a: 1]), :b, 2)
      Xb5.Tree.new([a: 1, b: 2])
      iex> Xb5.Tree.put_new(Xb5.Tree.new([a: 1, b: 2]), :a, 3)
      Xb5.Tree.new([a: 1, b: 2])

  """
  @spec put_new(t(), key(), value()) :: t()
  def put_new(%__MODULE__{size: size, root: root} = tree, key, value) do
    case :xb5_trees_node.insert_att(key, :eager, value, root) do
      :key_exists ->
        tree

      root ->
        %{tree | size: size + 1, root: root}
    end
  end

  @doc """
  Evaluates `fun` and puts the result under `key` in `tree` unless `key` is already present.

  This is useful when the value to put under `key` is expensive to calculate or generally
  difficult to setup and teardown again.

  ## Examples

      iex> tree = Xb5.Tree.new([a: 1])
      iex> fun = fn ->
      ...>   # some expensive operation here
      ...>   3
      ...> end
      iex> Xb5.Tree.put_new_lazy(tree, :a, fun)
      Xb5.Tree.new([a: 1])
      iex> Xb5.Tree.put_new_lazy(tree, :b, fun)
      Xb5.Tree.new([a: 1, b: 3])

  """
  @spec put_new_lazy(t(), key(), (-> value())) :: t()
  def put_new_lazy(%__MODULE__{size: size, root: root} = tree, key, fun) do
    case :xb5_trees_node.insert_att(key, :lazy, fun, root) do
      :key_exists ->
        tree

      root ->
        %{tree | size: size + 1, root: root}
    end
  end

  @doc """
  Returns a new tree excluding the entries from `tree` for which `fun` returns a truthy value.

  See also `filter/2`.

  ## Examples

      iex> Xb5.Tree.reject(Xb5.Tree.new([one: 1, two: 2, three: 3]), fn {_key, val} -> rem(val, 2) == 1 end)
      Xb5.Tree.new([two: 2])

  """
  @spec reject(t(key, value), ({key, value} -> as_boolean(term()))) :: t(key, value)
  def reject(tree, fun) do
    from_orddict(for pair <- to_list(tree), !fun.(pair), do: pair)
  end

  @doc """
  Puts a value under `key` only if `key` already exists in `tree`.

  If `key` is not present in `tree`, the tree is returned unchanged.

  ## Examples

      iex> Xb5.Tree.replace(Xb5.Tree.new([a: 1, b: 2]), :a, 3)
      Xb5.Tree.new([a: 3, b: 2])
      iex> Xb5.Tree.replace(Xb5.Tree.new([a: 1]), :b, 2)
      Xb5.Tree.new([a: 1])

  """
  @spec replace(t(), key(), value()) :: t()
  def replace(%__MODULE__{root: root} = tree, key, value) do
    case :xb5_trees_node.update_att(key, :eager, value, root) do
      :badkey ->
        tree

      root ->
        %{tree | root: root}
    end
  end

  @doc """
  Puts a value under `key` only if `key` already exists in `tree`.

  If `key` is not present in `tree`, a `KeyError` exception is raised.

  ## Examples

      iex> Xb5.Tree.replace!(Xb5.Tree.new([a: 1, b: 2]), :a, 3)
      Xb5.Tree.new([a: 3, b: 2])
      iex> Xb5.Tree.replace!(Xb5.Tree.new([a: 1]), :b, 2)
      ** (KeyError) key :b not found in:
      ...

  """
  @spec replace!(t(), key(), value()) :: t()
  def replace!(%__MODULE__{root: root} = tree, key, value) do
    case :xb5_trees_node.update_att(key, :eager, value, root) do
      :badkey ->
        raise KeyError, term: tree, key: key

      root ->
        %{tree | root: root}
    end
  end

  @doc """
  Replaces the value under `key` using the given function only if `key` already exists
  in `tree`.

  In comparison to `replace/3`, this can be useful when it's expensive to calculate the value.

  If `key` does not exist, the original tree is returned unchanged.

  ## Examples

      iex> Xb5.Tree.replace_lazy(Xb5.Tree.new([a: 1, b: 2]), :a, fn v -> v * 4 end)
      Xb5.Tree.new([a: 4, b: 2])
      iex> Xb5.Tree.replace_lazy(Xb5.Tree.new([a: 1, b: 2]), :c, fn v -> v * 4 end)
      Xb5.Tree.new([a: 1, b: 2])

  """
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

  @doc """
  Returns the number of entries in `tree`.

  ## Examples

      iex> Xb5.Tree.size(Xb5.Tree.new([a: 1, b: 2, c: 3]))
      3

  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{size: size}) do
    size
  end

  @doc """
  Returns the entry immediately preceding `key` in `tree`.

  If `tree` contains an entry with a key strictly less than `key`, it is returned as
  `{prev_key, value}`. Otherwise returns `:error`.

  ## Examples

      iex> Xb5.Tree.smaller(Xb5.Tree.new([a: 1, b: 2, c: 3]), :b)
      {:a, 1}
      iex> Xb5.Tree.smaller(Xb5.Tree.new([a: 1, b: 2, c: 3]), :a)
      :error

  """
  @spec smaller(t(key, value), value) :: {key, value} | :error
  def smaller(%__MODULE__{root: root}, element) do
    case :xb5_trees_node.smaller(element, root) do
      {_, _} = found -> found
      :none -> :error
    end
  end

  @doc """
  Returns the entry with the smallest key in `tree`.

  Raises `ArgumentError` if `tree` is empty.

  ## Examples

      iex> Xb5.Tree.smallest!(Xb5.Tree.new([a: 1, b: 2, c: 3]))
      {:a, 1}
      iex> Xb5.Tree.smallest!(Xb5.Tree.new([]))
      ** (ArgumentError) tree is empty

  """
  @spec smallest!(t(key, value)) :: {key, value}
  def smallest!(%__MODULE__{size: size, root: root}) do
    if size === 0 do
      raise ArgumentError, "tree is empty"
    else
      :xb5_trees_node.smallest(root)
    end
  end

  @doc """
  Takes all entries corresponding to the given `keys` in `tree` and extracts them into a
  separate tree.

  Returns a tuple with the new tree and the old tree with removed keys.

  Keys for which there are no entries in `tree` are ignored.

  ## Examples

      iex> Xb5.Tree.split(Xb5.Tree.new([a: 1, b: 2, c: 3]), [:a, :c, :e])
      {Xb5.Tree.new([a: 1, c: 3]), Xb5.Tree.new([b: 2])}

  """
  @spec split(t(), [key()]) :: {t(), t()}
  def split(%__MODULE__{root: root}, keys) do
    rev_keys = keys |> :lists.usort() |> :lists.reverse()

    root
    |> :xb5_trees_node.to_rev_list()
    |> split_recur(rev_keys, 0, [], 0, [])
  end

  @doc """
  Splits `tree` into two trees according to the given function `fun`.

  `fun` receives each `{key, value}` pair in `tree` as its only argument. Returns a tuple
  with the first tree containing all the entries for which `fun` returned a truthy value,
  and a second tree with all the entries for which `fun` returned a falsy value (`false`
  or `nil`).

  ## Examples

      iex> {while_true, while_false} = Xb5.Tree.split_with(Xb5.Tree.new([a: 1, b: 2, c: 3, d: 4]), fn {_k, v} -> rem(v, 2) == 0 end)
      iex> while_true
      Xb5.Tree.new([b: 2, d: 4])
      iex> while_false
      Xb5.Tree.new([a: 1, c: 3])

      iex> {while_true, while_false} = Xb5.Tree.split_with(Xb5.Tree.new(), fn {_k, v} -> v > 50 end)
      iex> while_true
      Xb5.Tree.new([])
      iex> while_false
      Xb5.Tree.new([])

  """
  @spec split_with(t(), ({key(), value()} -> as_boolean(term()))) :: {t(), t()}
  def split_with(%__MODULE__{root: root}, fun) do
    root
    |> :xb5_trees_node.to_rev_list()
    |> split_with_recur(fun, 0, [], 0, [])
  end

  @doc """
  Returns a new tree with all the key-value pairs in `tree` where the key is in `keys`.

  If `keys` contains keys that are not in `tree`, they're simply ignored.

  ## Examples

      iex> Xb5.Tree.take(Xb5.Tree.new([a: 1, b: 2, c: 3]), [:a, :c, :e])
      Xb5.Tree.new([a: 1, c: 3])

  """
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

  @doc """
  Converts `tree` to a list.

  Each key-value pair in the tree is converted to a two-element tuple `{key, value}` in the
  resulting list. Entries are returned in ascending key order.

  ## Examples

      iex> Xb5.Tree.to_list(Xb5.Tree.new([a: 1, b: 2]))
      [a: 1, b: 2]
      iex> Xb5.Tree.to_list(Xb5.Tree.new([{1, "one"}, {2, "two"}]))
      [{1, "one"}, {2, "two"}]

  """
  @spec to_list(t(key, value)) :: [value]
  def to_list(%__MODULE__{root: root}) do
    :xb5_trees_node.to_list(root)
  end

  @doc """
  Updates the `key` in `tree` with the given function.

  If `key` is present in `tree` then the existing value is passed to `fun` and its result
  is used as the updated value of `key`. If `key` is not present in `tree`, `default` is
  inserted as the value of `key`. The default value will not be passed through the update
  function.

  ## Examples

      iex> Xb5.Tree.update(Xb5.Tree.new([a: 1]), :a, 13, fn existing_value -> existing_value * 2 end)
      Xb5.Tree.new([a: 2])
      iex> Xb5.Tree.update(Xb5.Tree.new([a: 1]), :b, 11, fn existing_value -> existing_value * 2 end)
      Xb5.Tree.new([a: 1, b: 11])

  """
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

  @doc """
  Updates `key` with the given function.

  If `key` is present in `tree` then the existing value is passed to `fun` and its result
  is used as the updated value of `key`. If `key` is not present in `tree`, a `KeyError`
  exception is raised.

  ## Examples

      iex> Xb5.Tree.update!(Xb5.Tree.new([a: 1]), :a, &(&1 * 2))
      Xb5.Tree.new([a: 2])
      iex> Xb5.Tree.update!(Xb5.Tree.new([a: 1]), :b, &(&1 * 2))
      ** (KeyError) key :b not found in:
      ...

  """
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

  @doc """
  Returns the size and root node of `tree` as `%{size: n, root: node}`.

  Pass the result to `:xb5_trees.wrap/1` to obtain a proper `:xb5_trees` term.

  ## Examples

      iex> %{size: size} = Xb5.Tree.unwrap(Xb5.Tree.new([a: 1, b: 2, c: 3]))
      iex> size
      3

  """
  @spec unwrap(t(key, value)) :: :xb5_trees.unwrapped_tree(key, value)
  def unwrap(%__MODULE__{size: size, root: root}) do
    %{size: size, root: root}
  end

  @doc """
  Returns all values from `tree` in ascending key order.

  ## Examples

      iex> Xb5.Tree.values(Xb5.Tree.new([a: 1, b: 2]))
      [1, 2]

  """
  @spec values(t()) :: [value()]
  def values(%__MODULE__{root: root}) do
    :xb5_trees_node.values(root)
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
    root = :xb5_trees_node.from_orddict(size, orddict)
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
  defp fetch_bang_not_found(tree, key), do: raise(KeyError, term: tree, key: key)

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
        size2 = size2 + length(list)
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

    def reduce(%Xb5.Tree{root: root}, acc, fun) do
      :xb5_trees_node.elixir_reduce(fun, acc, root)
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

      {concat(["Xb5.Tree.new(", doc, ")"]), %{opts | limit: limit}}
    end
  end
end
