# xb5_elixir

Elixir wrapper library around the [`xb5`](https://github.com/g-andrade/xb5) Erlang B-tree library.
Provides idiomatic Elixir structs and protocols over three Erlang modules:

- `:xb5_sets` → `Xb5.Set` — ordered set (drop-in for `gb_sets`)
- `:xb5_trees` → `Xb5.Tree` — ordered key-value store (drop-in for `gb_trees`)
- `:xb5_bag` → `Xb5.Bag` — ordered multiset with order-statistic ops (rank, percentile, nth)

All three are B-trees of order 5. All Erlang types are opaque. `wrap/unwrap` convert to/from
`%{size: n, root: node}` maps for cross-language interop.

## Dev commands

```bash
mix test           # run tests
mix test --cover   # run with coverage (93% threshold enforced)
mix credo          # linter
mix dialyzer       # type checking
```

## Project layout

```
lib/xb5/
  bag.ex           Xb5.Bag — use as style template
  set.ex           Xb5.Set
  tree.ex          Xb5.Tree
test/xb5/
  bag_test.exs
  set_test.exs
  tree_test.exs
test/extra/
  xb5_bag_test_utils.ex
  xb5_set_test_utils.ex
  xb5_tree_test_utils.ex
deps/xb5/          Erlang source — read before assuming the API
  CLAUDE.md        Erlang library overview
  src/xb5_bag.erl, xb5_trees.erl, xb5_sets.erl   Public Erlang API (source of truth)
```

## API design rules

- All public functions declared in **alphabetical order**.
- No `fold/3`, `iterator/2`, `iterator_from/3`, `next/1` — Enumerable covers iteration.
- `from_erlang/1` is NOT separate — folded into `new/1` (tries `:xb5_*.unwrap/1`, falls back to Enumerable).
- `filter/2` fun is wrapped for Elixir truthy semantics.
- `map/2` on Set returns a new set (not a list); on Tree transforms values.
- `symmetric_difference/2` implemented at Elixir level as `union(difference(a,b), difference(b,a))`.
- Bang functions (`largest!/1`, `smallest!/1`, `pop_largest!/1`, `pop_smallest!/1`, `fetch_index!/2`, etc.)
  raise `ArgumentError` on empty collections and `KeyError` on missing keys.
- `fetch_index/2`, `fetch_index!/2`, `get_index/3` are **0-based** (Elixir idiom).

### Bag-specific

- `push/2` — always inserts a new copy even if already present.
- `put/2` — idempotent (no-op if already present), analogous to `MapSet.put/2` / `gb_sets:add/2`.
- No `put_new` on Bag.

## Deferred (not yet exposed in Elixir)

These Erlang functions exist but are pending clearer API design:

- `Xb5.Bag`: `nth/2`, `rank/2`, `rank_smaller/2`, `rank_larger/2`, `map/2`
- Corresponding tests are tagged `@tag :skip`.

## Testing

- For **core data structure behaviour**: translate tests directly from the Erlang CT suites.
- For **Elixir-exclusive functionality** (Enumerable, Collectable, Inspect, and other protocol
  implementations): invent appropriate test cases, since these have no Erlang counterpart.
- `test/extra/` contains shared test helpers.
- `warnings_as_errors: true` is set in test env.

## Before adding new functions

Re-read `deps/xb5/src/` — the Erlang library may have been extended since the last session.
