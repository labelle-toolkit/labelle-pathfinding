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

Retargets are **idempotent**: `navigate`/`moveTo` clear any prior walk, the
pending ring, and the persisted order before starting the new one.

### Grid navigation

Add one `NavGrid` component to the scene with positive `cols`, `rows`, and
`cell`. Use `NavObstacle` for blocked rectangles and `NavCost` for terrain
rectangles. Both are centered on the entity's local `Position` plus their
offsets. Obstacles expand by the grid's `agent_radius`; overlapping terrain
uses the highest authored cost. Use root entities for footprints and grid
walkers so their local positions are also their world positions.

```zig
_ = pathfinder.Controller.navigateTo(game, worker, point);
_ = pathfinder.Controller.navigateAdjacent(game, worker, tree);
const reachable = pathfinder.Controller.gridReachableAdjacent(game, worker, tree);
```

`navigateTo` snaps a blocked target to the nearest cell in the walker's
region. `navigateAdjacent` chooses the cheapest reachable edge neighbor.
`gridReachable` checks the supplied cell itself. `gridWalkCost` returns the
route cost in tenths of an axial cell-entry cost. Terrain cost affects route
selection; movement uses `MovementSpeed`. To inspect the grid, call
`drawGridGizmos` with the `GridNavigation` category enabled.

An agent whose current cell becomes blocked can step into a free edge
neighbor and continue its route. If no free edge neighbor leads to the
destination, the controller reports that there is no route.

Automatic footprint updates require an engine containing [#937](https://github.com/labelle-toolkit/labelle-engine/pull/937).
Add this receiver as `hooks/grid_navigation.zig` in an assembled game:

```zig
const engine = @import("engine");
const pathfinder = @import("pathfinder");

pub const GridNavigation = struct {
    ctx: engine.HookContext = .{},

    pub fn component_changed(self: *GridNavigation, payload: anytype) void {
        pathfinder.Controller.componentChanged(self.ctx.game(), payload);
    }
};
```

The hook queues footprint changes. Grid queries and the existing
`Controller.advance` driver apply those changes and replan affected routes.
Use Game setters to get automatic notifications. For raw component writes,
call `refreshFootprint` after the mutation. Call `rebuildGrid` after
changing the scene's grid configuration at runtime.
An invalid rebuild logs the error, fails active grid walks, and rejects
new grid commands until a valid configuration is rebuilt.

Grid arrivals add a `.grid` destination to `pathfinder__arrived`. The
existing `node_entity` field is zero for grid arrivals. Subscribe to
`pathfinder__grid_changed` for committed occupancy or cost updates.

To run the real-engine integration fixture, check out `labelle-engine` with
#937 and a compatible `labelle-core` as siblings of this repo, then run
`zig build test` from `tests/engine-grid`.

### Queries (reads; never mutate)

```zig
pathfinder.Controller.reachable(game, a, b);          // bool — any route between their nearest nodes?
pathfinder.Controller.reachableNode(game, e, node);   // bool — entity → specific node
pathfinder.Controller.reachablePosition(game, e, pos);// bool — entity → world position
pathfinder.Controller.walkDistance(game, a, b);       // f32 — path cost; inf when disconnected;
                                                      //       Euclidean before the graph exists.
                                                      //       THE "nearest X" selector metric.
pathfinder.Controller.distance(game, a, b);           // ?f32 — lower-level primitive behind the above
pathfinder.Controller.isNavigating(game, e);          // walking in any navigation mode
pathfinder.Controller.nodeCount(game);
pathfinder.Controller.graphEpoch(game);               // bumps every rebuild (poll twin of graph_rebuilt)
pathfinder.Controller.findClosestNode(game, pos);
pathfinder.Controller.targetPosition(game, entity);   // CMN-preferred nav target for an entity
```

For a synchronous destination scan, reuse the origin resolution:

```zig
var distances = pathfinder.Controller.walkDistancesFrom(game, source);
// Inside a read-only candidate loop:
const cost = distances.to(destination);
```

The first candidate resolves the origin's world position and its validated
nearest node; subsequent candidates reuse that result. Empty scans do no
resolution work. Targets still resolve live, and distances retain `walkDistance`'s
pre-graph Euclidean and unreachable-infinity behavior. Discard the query before
moving/reparenting the origin or its ancestors, changing the graph or world, or
advancing the simulation. It is not a cross-frame cache or a thread-safe handle.
The query uses the existing position-validated node cache; the ECS
`ClosestMovementNode` component alone does not supply that freshness contract.

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
