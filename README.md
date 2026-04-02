# xb5_elixir

[![](https://img.shields.io/hexpm/v/xb5_elixir.svg?style=flat)](https://hex.pm/packages/xb5_elixir)

Elixir wrapper around [xb5](https://github.com/g-andrade/xb5), an Erlang library of
[B-tree](https://en.wikipedia.org/wiki/B-tree)-based (order 5) sorted containers.
Provides idiomatic Elixir structs with full `Enumerable`, `Collectable`, and `Inspect`
support.

If you need ordered collections, `xb5` is [**1.2–2.5× faster**](https://www.gandrade.net/xb5_benchmark/report_amd_ryzen7_5700g.html)
than Erlang/OTP's `gb_sets` and `gb_trees` for most operations, with equal or lower heap
usage — and those gains carry over directly to `xb5_elixir`.

Three modules are provided:

- **`Xb5.Set`** — ordered set
- **`Xb5.Tree`** — ordered key-value store
- **`Xb5.Bag`** — ordered [multiset](https://en.wikipedia.org/wiki/Set_(abstract_data_type)#Multiset)
  with order-statistic operations (percentile, rank) and O(log n) random access via `Enum`

## Installation

```elixir
def deps do
  [
    {:xb5_elixir, "~> 0.1"}
  ]
end
```

## Usage

### Xb5.Set

An ordered set. Supports all standard set operations and efficient traversal in sorted order.

```elixir
iex> set = Xb5.Set.new([3, 1, 2, 1])
Xb5.Set.new([1, 2, 3])
iex> Xb5.Set.member?(set, 2)
true
iex> Xb5.Set.smallest!(set)
1
iex> Xb5.Set.largest!(set)
3
iex> Xb5.Set.smaller(set, 2)
{:ok, 1}
iex> Xb5.Set.larger(set, 2)
{:ok, 3}
```

```elixir
iex> a = Xb5.Set.new(1..5)
iex> b = Xb5.Set.new(3..7)
iex> Xb5.Set.union(a, b)
Xb5.Set.new([1, 2, 3, 4, 5, 6, 7])
iex> Xb5.Set.difference(a, b)
Xb5.Set.new([1, 2])
iex> Xb5.Set.intersection(a, b)
Xb5.Set.new([3, 4, 5])
```

### Xb5.Tree

An ordered key-value store. Its API closely mirrors `Map`.

```elixir
iex> tree = Xb5.Tree.new(a: 1, b: 2, c: 3)
Xb5.Tree.new([a: 1, b: 2, c: 3])
iex> Xb5.Tree.get(tree, :a)
1
iex> Xb5.Tree.fetch(tree, :d)
:error
iex> Xb5.Tree.smallest!(tree)
{:a, 1}
iex> Xb5.Tree.largest!(tree)
{:c, 3}
iex> tree = Xb5.Tree.put(tree, :d, 4)
Xb5.Tree.new([a: 1, b: 2, c: 3, d: 4])
iex> Xb5.Tree.keys(tree)
[:a, :b, :c, :d]
iex> Xb5.Tree.smaller(tree, :c)
{:b, 2}
iex> Xb5.Tree.larger(tree, :b)
{:c, 3}
```

### Xb5.Bag

An ordered multiset: like `Xb5.Set`, but allows multiple occurrences of the same value.
Supports order-statistic operations such as `percentile/3` and `percentile_bracket/3`.

`push/2` always inserts a new copy; `put/2` is idempotent, analogous to `Xb5.Set.put/2`.

```elixir
iex> bag = Xb5.Bag.new() |> Xb5.Bag.push(:x) |> Xb5.Bag.push(:x)
Xb5.Bag.new([:x, :x])
iex> Xb5.Bag.size(bag)
2
iex> Xb5.Bag.put(bag, :x) == bag
true
```

Order statistics on numerical data:

```elixir
iex> latencies = Xb5.Bag.new([12, 14, 14, 15, 15, 18, 20, 25, 30, 100])
iex> Xb5.Bag.count(latencies, 15)
2
iex> Xb5.Bag.percentile_bracket(latencies, 0.00)
{:exact, 12}
iex> Xb5.Bag.percentile_bracket(latencies, 0.50)
{:between, 15, 18, 0.5}
iex> Xb5.Bag.percentile(latencies, 0.50)
{:value, 16.5}
iex> Xb5.Bag.percentile(latencies, 0.75)
{:value, 23.75}
```

`percentile_bracket/3` returns `{:exact, x}` when the percentile falls exactly on one
element, or `{:between, lo, hi, t}` when it falls between two — where `t` is the linear
interpolation weight. The default method is `inclusive` (equivalent to Excel
`PERCENTILE.INC`); `exclusive` and `nearest_rank` are also available via the `opts`
argument. `percentile/3` performs the interpolation and returns `{:value, result}`.

## Protocols

All three modules implement `Enumerable`, `Collectable`, and `Inspect`, making them
compatible with `Enum`, `Stream`, comprehensions, and `Kernel.inspect/1`.

```elixir
iex> set = Xb5.Set.new(1..10)
iex> set |> Enum.filter(&rem(&1, 2) == 0) |> Enum.sum()
30
```

```elixir
iex> tree = Xb5.Tree.new([a: 1, b: 2, c: 3])
iex> for {k, v} <- tree, do: {k, v * 2}
[a: 2, b: 4, c: 6]
```

```elixir
iex> bag = Xb5.Bag.new([1, 2, 3])
iex> Enum.into([4, 5], bag)
Xb5.Bag.new([1, 2, 3, 4, 5])
```

`Enum.count/1` and `Enum.member?/2` run in O(1) and O(log n) respectively for all three.
`Xb5.Bag` additionally provides O(log n) random access: because it is an order-statistic
tree, `Enum.at/2` and other index-based operations locate elements by rank without
traversing from the start.

### Comparison semantics

All three collections use `==` (non-strict) for element equality, consistent with Erlang
term order, which underlies the B-tree's sorting. This means `1` and `1.0` are treated as
the same element. `Enumerable.member?/2` follows the same semantics:

```elixir
iex> set = Xb5.Set.new([1, 2, 3])
iex> Enum.member?(set, 1.0)
true
```

This differs from `MapSet`, which uses strict `===` comparison.

## Erlang interop

The Elixir structs and the Erlang `xb5` opaque records are two different packages around
the same content: a `size` integer and a `root` node term. `new/1` extracts that content
from an Erlang record via `:xb5_*.unwrap/1` (which does a quick read-only validation pass);
`unwrap/1` hands it back as `%{size: n, root: node}`. No tree data is duplicated.

```elixir
iex> erlang_set = :xb5_sets.from_list([1, 2, 3])
iex> elixir_set = Xb5.Set.new(erlang_set)
Xb5.Set.new([1, 2, 3])
iex> Xb5.Set.unwrap(elixir_set).size
3
```

## Benchmarks

See the [xb5 benchmark report](https://www.gandrade.net/xb5_benchmark/report_amd_ryzen7_5700g.html)
for detailed comparisons against `gb_sets`/`gb_trees` across 50+ operations and collection
sizes up to 15,000 elements. A second report on an
[Intel i5-3550](https://www.gandrade.net/xb5_benchmark/report_intel_i5_3550.html) is also
available.

## License

MIT License. Copyright (c) 2025–2026 Guilherme Andrade.
