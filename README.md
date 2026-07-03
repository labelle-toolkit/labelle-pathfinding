# Labelle Pathfinding

Navigation for [labelle-toolkit](https://github.com/labelle-toolkit) games — and a standalone
pathfinding algorithm core. Since **v4**, the plugin owns *everything movement*: the node
graph, route computation (Floyd-Warshall), **both walkers** (graph navigation and
straight-line `moveTo`), arrival handling, and the persisted walk order. Entity positions
stay in **your ECS** — the walkers mutate them through the game API; the package never
owns coordinates.

Two layers, one package — each usable without the other:

1. **Navigation Controller** (the headline) — an ECS-integrated, duck-typed
   (`game: anytype`) controller for labelle-engine games. Never imports the engine.
2. **Algorithm core** (`pathfinding.algo.*`) — A*, Floyd-Warshall (incl. SIMD/parallel
   variants), QuadTree spatial indexing, heuristics, grid types. No ECS, no game.

## Requirements

- Zig 0.16.0+

## Installation

**labelle-engine games** — declare the plugin in `project.labelle` (the name **must** be
`pathfinder`; both `@import("pathfinder")` call sites and the `pathfinder__*` event tags
depend on it):

```zig
.plugins = .{
    .{ .name = "pathfinder", .repo = "github.com/labelle-toolkit/labelle-pathfinding", .version = "4.0.0" },
},
```

**Standalone** (algorithm core / pure engine):

```bash
zig fetch --save https://github.com/labelle-toolkit/labelle-pathfinding/archive/refs/tags/v4.0.0.tar.gz
```

## Usage — Navigation Controller (labelle-engine games)

Communication follows the three-channel model: **commands down, queries down, events up.**

### Commands (plain fns; acceptance via `Result`, effects via events)

```zig
const pathfinder = @import("pathfinder");

_ = pathfinder.Controller.navigate(game, entity, target_pos, @src()); // graph walk
_ = pathfinder.Controller.moveTo(game, entity, target_pos);           // straight-line (off-graph:
                                                                      // ship hops, wander steps)
pathfinder.Controller.cancel(game, entity);        // stop walking — a site that marks an entity
                                                   // "can't move" (fight, stun, death) MUST cancel;
                                                   // the walker is domain-blind by design
pathfinder.Controller.requestRepath(game, entity); // re-resolve the entity's ClosestMovementNode now
pathfinder.Controller.removeNode(game, node_id);   // tombstone a node (deconstruction drains)
pathfinder.Controller.rebuildGraph(game);          // explicit full rebuild
```

Retargets are **idempotent**: `navigate`/`moveTo` clear any prior walk (either mode), the
pending ring, and the persisted order before starting the new one.

### Queries (reads; never mutate)

```zig
pathfinder.Controller.reachable(game, a, b);          // bool — any route between their nearest nodes?
pathfinder.Controller.reachableNode(game, e, node);   // bool — entity → specific node
pathfinder.Controller.reachablePosition(game, e, pos);// bool — entity → world position
pathfinder.Controller.walkDistance(game, a, b);       // f32 — path cost; inf when disconnected;
                                                      //       Euclidean before the graph exists.
                                                      //       THE "nearest X" selector metric.
pathfinder.Controller.distance(game, a, b);           // ?f32 — lower-level primitive behind the above
pathfinder.Controller.isNavigating(game, e);          // walking? (graph OR direct)
pathfinder.Controller.nodeCount(game);
pathfinder.Controller.graphEpoch(game);               // bumps every rebuild (poll twin of graph_rebuilt)
pathfinder.Controller.findClosestNode(game, pos);
pathfinder.Controller.targetPosition(game, entity);   // CMN-preferred nav target for an entity
```

### Events (the only outbound channel — subscribe from game hooks)

| Event | Payload | Fires when |
|---|---|---|
| `pathfinder__arrived` | `{ entity, node_entity }` | any walk settles at its destination (incl. `.redundant` already-there calls) |
| `pathfinder__navigation_failed` | `{ entity, reason }` | graph changed mid-walk with no reroute, or a loaded order can't re-issue |
| `pathfinder__graph_rebuilt` | `{ epoch }` | the node graph was (re)built — invalidate node-derived caches |
| `pathfinder__node_removed` | `{ node_id }` | a node was tombstoned |

### Components

| Component | Who writes it | Save |
|---|---|---|
| `MovementNode` / `MovementStair` | your scenes/prefabs (the graph) | saveable / marker |
| `MovementSpeed { speed }` | your prefabs (px/s; plugin default 200 when absent) | saveable |
| `Navigating` | the plugin — the persisted walk order; mid-walk saves resume on load via the advance rehydration sweep | saveable |
| `ClosestMovementNode` | the plugin (arrivals, `requestRepath`, epoch sweeps) | transient |
| `ControllerState` | the plugin (singleton runtime state) | transient |

### What your game still does

One thin, pause-gated driver script calling `pathfinder.Controller.advance(game, dt)`
each frame — the plugin can't read your pause component across the module boundary.
Graph rebuilds are automatic (node-count change detection, one rebuild per advance);
no markers, no debounce scripts.

## Usage — pure engine (no ECS, no game)

```zig
const pf = @import("labelle_pathfinding");

var engine = pf.PathfinderWith(u64, struct {}).init(allocator, .{
    .max_vertical_distance = 200.0,
    .max_horizontal_distance = 78.0,
});
defer engine.deinit();

const a = try engine.addNode(.{ .x = 0, .y = 0 }, false);
const b = try engine.addNode(.{ .x = 50, .y = 0 }, false);
_ = try engine.navigate(7, a, b, 200.0); // entity 7, speed px/s

// Your tick ctx provides positions and applies movement — and may
// observe settles via optional callbacks:
//   getEntityPosition(id) ?Position   moveEntity(id, dx, dy)
//   onArrived(id, goal_node)          onPathInvalidated(id, goal_node)
engine.tick(&ctx, dt);
```

## Usage — algorithm core

```zig
const pf = @import("labelle_pathfinding");
var astar = pf.algo.AStar.init(allocator);
var fw = pf.algo.FloydWarshallOptimized(.{}).init(allocator); // SIMD; .Parallel for large graphs
var qt = pf.algo.QuadTree.init(allocator, bounds);
```

## Development

```bash
zig build test   # unit tests
zig build spec   # zspec navigation tests
```
