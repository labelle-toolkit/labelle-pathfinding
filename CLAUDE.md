# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
zig build test   # unit tests (tests/nav/*)
zig build spec   # zspec navigation behavior tests
```

There are no example or benchmark targets — those were v2-era and removed
with the v3 repurpose.

## Requirements

Zig 0.16.0+ (`minimum_zig_version` in build.zig.zon).

## Architecture (v4)

The package is the labelle-engine **navigation plugin** (`.name = "pathfinder"`
in a game's project.labelle — the name is load-bearing: `@import("pathfinder")`
call sites and the `pathfinder__*` event tags both depend on it). Since v4 it
owns everything movement; the consuming game keeps ONE pause-gated driver
script calling `Controller.advance(game, dt)`.

### Layers

- **`src/root.zig`** — module root. Declares the plugin `Events`
  (`arrived`, `navigation_failed`, `graph_rebuilt`, `node_removed`) **inline** —
  the assembler AST-walks this exact file; a re-export alias would be silently
  invisible. Re-exports the full surface from `pathfinding.zig`.
- **`src/pathfinding.zig`** — the surface aggregator: nav layer at top level,
  algorithm core under `algo.*`.
- **`src/nav/`** — the navigation layer:
  - `controller.zig` — the plugin `Controller` (RFC-plugin-controllers):
    commands (`navigate`, `moveTo`, `cancel`, `requestRepath`, `removeNode`,
    `rebuildGraph`), queries (`reachable*`, `walkDistance`, `distance`,
    `isNavigating`, `graphEpoch`, `targetPosition`, …), the settle path
    (CMN refresh + `Navigating` removal + event emission), the `moveTo`
    direct-walk tick, the `Navigating` rehydration sweep (mid-walk saves
    resume on load), count-based graph-rebuild detection, and the CMN
    epoch sweep. State lives behind the `ControllerState` singleton
    (type-erased pointer; transient).
  - `engine.zig` — pure `PathfinderWith(GameId, Hooks)`: graph + FW matrix +
    the graph walker. `tick(ctx, dt)` calls `ctx.getEntityPosition`/`moveEntity`
    and, when declared (`@hasDecl`-gated), `ctx.onArrived`/`onPathInvalidated`.
  - `components.zig` — `MovementNode` (saveable), `MovementStair` (marker),
    `ClosestMovementNode` (transient), `Navigating` (saveable walk order),
    `MovementSpeed` (saveable, per-entity px/s).
  - `graph.zig` / `floyd_warshall.zig` / `movement_path.zig` — graph storage,
    axis-aligned auto-connection (horizontal cap 78 px, vertical via stairs,
    cap 200 px), FW matrix, per-entity path state.
- **`src/` (algo core)** — standalone: `a_star.zig`, `floyd_warshall_optimized.zig`
  (SIMD/parallel variants), `quad_tree.zig`, `heuristics.zig`, `distance_graph.zig`,
  `types.zig`. Namespaced as `pathfinding.algo.*`.

### Key invariants

- **Positions live in the consumer's ECS** — the walkers mutate through the
  game API (`getPosition`/`setPosition`); the package never owns coordinates
  (the v2 position-owning engine was deleted for exactly this).
- **The walker is domain-blind** — any game-side "can't move" marker site
  (fight, stun, death) must call `Controller.cancel`. Documented contract
  since v3 (`GameCtx.moveEntity`), unchanged in v4.
- **Retargets are idempotent** — `navigate`/`moveTo` clear the prior route,
  ring entry, direct-move entry, AND the persisted `Navigating` before
  starting anew, so failed retargets can't be resurrected by the rehydration
  sweep.
- **Events are sparse** (settles, rebuilds, tombstones) — continuous state is
  behind the queries. The plugin never subscribes to game events.
- **World positions** (`getWorldPosition`) everywhere positions are compared —
  parented entities (storages under rooms) are meaningless in local coords.

## Testing

`tests/nav/*_test.zig`, aggregated by `tests/nav/root.zig`. Controller logic
that needs a full game (settle flows, rehydration, CMN sweeps) is
integration-covered by the consuming game (flying-platform-labelle's bandit /
transport / save-load scenes) — this repo deliberately has no mock game.
Engine-level behavior (walking, invalidation, settle callbacks) and pure
helpers (`directStep`, `nodesReachable`, cache validity) are unit-tested here.
