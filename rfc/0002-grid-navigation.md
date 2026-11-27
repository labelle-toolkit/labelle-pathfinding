# RFC 0002: Grid Navigation

**Status:** draft
**Target:** labelle-toolkit/labelle-pathfinding (written against 4.2.1)

## Summary

Add a grid navigation mode to the `pathfinder` plugin: a cost grid built
from footprint components on entities, searched with A\*, and updated
incrementally as the world changes. It sits beside the existing node-graph
mode and reuses the same walker, the same `Navigating` order and the same
events. A game asks an entity to walk to a point, or to walk up next to
another entity, and hears `pathfinder__arrived` when it gets there.

## Motivation

The node-graph mode fits worlds whose walkable space is authored: rooms,
corridors, stairs. It does not fit colony and builder games in the style of
RimWorld, Dwarf Fortress or Oxygen Not Included, where:

- **The walkable space is open ground**, interrupted by scattered obstacles
  (trees, rocks, buildings). There is no natural set of nodes to author.
- **The map changes all the time.** Felling a tree opens ground; building a
  wall closes it. Today any change to the node set rebuilds the whole graph
  and its all-pairs Floyd-Warshall table.
- **Work happens next to things, not on them.** A tree occupies its own cell.
  The worker must reach any free cell beside it.
- **Terrain has a price.** Deep snow, mud or water should be slower than a
  cleared path, and the route should take that into account.
- **"Can I get there?" is asked far more often than "how?".** Choosing the
  nearest reachable job should not need a full search per candidate.

The first consumer is Long Snow, a prototype where a wanderer on a snowfield
will be told to fell pines and build things. It has about 65 obstacles on an
800x600 field today, with no collision and keyboard-only movement.

## Non-goals

These belong to other packages or to later RFCs:

- Job queues, target reservation and work timers (a task system's concern).
- Avoidance between moving agents; agents may overlap in v1.
- Multiple levels (z), ladders or flying.
- Obstacles that move every frame.
- Hierarchical search, flow fields and search time-slicing. The design leaves
  room for them; v1 does not include them.

## Design

### Overview

```
entities with NavObstacle / NavCost ──▶ grid (blocked + cost per cell)
                                          │
                 regions (connected-component id per cell) ◀─┤
                                          │
navigateTo / navigateAdjacent ──▶ grid A* ──▶ smoothed waypoints
                                          │
                     existing walker ◀────┘──▶ pathfinder__arrived
```

Entity positions stay in the game's ECS, as today. The plugin owns the grid,
the regions and the paths.

### Terminology and package boundary

`graph`, `direct` and `grid` are navigation modes. A* and Floyd-Warshall
are search algorithms. Neither term refers to a runtime provider (such as
bgfx or raylib) or a graphics API (such as Vulkan or OpenGL).

All navigation modes live in `labelle-pathfinding`, on the same main branch,
and share the walker, orders, persistence and events. Grid navigation does
not introduce an implementation branch or a separate plugin package.

### Components (authored by the game)

```zig
/// One per scene. Declares the grid. Without it the grid mode is off and
/// the plugin behaves exactly as in 4.2.
pub const NavGrid = struct {
    cell: f32 = 16,          // cell size in px
    origin_x: f32 = 0,       // world position of the grid's top-left corner
    origin_y: f32 = 0,
    cols: u32 = 0,
    rows: u32 = 0,
    default_cost: u8 = 10,   // cost of crossing one free cell
    agent_radius: f32 = 0,   // obstacles are grown by this much
};

/// This entity blocks the cells under a rectangle on the ground.
/// The rectangle is `width` x `height` px, centred on the entity's Position
/// plus (`offset_x`, `offset_y`).
pub const NavObstacle = struct {
    width: f32 = 0,
    height: f32 = 0,
    offset_x: f32 = 0,
    offset_y: f32 = 0,
};

/// This entity changes the cost of the cells under a rectangle, without
/// blocking them. Same rectangle convention as NavObstacle. Where several
/// overlap, the last one stamped wins.
pub const NavCost = struct {
    width: f32 = 0,
    height: f32 = 0,
    offset_x: f32 = 0,
    offset_y: f32 = 0,
    cost: u8 = 10,
};
```

A cell is blocked when any part of an obstacle rectangle (after growing it by
`agent_radius`) overlaps it. Rectangles are enough for v1: a tree trunk is a
small square, a cabin a wide one.

### Commands

```zig
/// Walk to the free cell containing `target`, or the nearest free cell in the
/// same region if `target` is blocked.
pathfinder.Controller.navigateTo(game, entity, target_pos) Result

/// Walk to any free cell that touches `target_entity`'s NavObstacle.
/// Picks the one with the cheapest path.
pathfinder.Controller.navigateAdjacent(game, entity, target_entity) Result

/// Re-stamp one entity's footprint after its Position or footprint changed.
pathfinder.Controller.refreshFootprint(game, entity) void

/// Throw the grid away and rebuild it from every footprint in the world.
pathfinder.Controller.rebuildGrid(game) void
```

`cancel`, `isNavigating` and `MovementSpeed` work unchanged. Both new commands
return the existing `Result`: `accepted`, `redundant` when already there,
`deferred` before the grid exists, `rejected(.no_path)` when the goal is in
another region.

`navigate` and `moveTo` keep their current meaning (node graph and straight
line). See "Open questions" for whether `navigate` should dispatch instead.

### Queries

```zig
pathfinder.Controller.gridReachable(game, entity, pos) bool          // region compare, O(1)
pathfinder.Controller.gridReachableAdjacent(game, entity, target) bool
pathfinder.Controller.gridWalkCost(game, entity, pos) ?u32           // runs a search
pathfinder.Controller.isBlocked(game, pos) bool
pathfinder.Controller.cellCost(game, pos) ?u8                        // null when blocked or off-grid
pathfinder.Controller.gridEpoch(game) u64                            // bumps on every grid change
```

`gridReachable*` only compare region ids, so a task system can filter a long
list of candidate jobs cheaply before asking for one real path.

### Events

| Event | Payload | Fires when |
|---|---|---|
| `pathfinder__arrived` | existing fields plus optional `destination` (below) | a walk reaches its resolved destination |
| `pathfinder__navigation_failed` | existing, `reason = .path_invalidated` or `.no_path` | the grid changed under a walk and no route is left |
| `pathfinder__grid_changed` (new) | `{ epoch, min_col, min_row, max_col, max_row }` | cells were re-stamped; the rectangle bounds the change |

The arrival payload keeps `entity` and `node_entity` unchanged and adds
`destination`, a nullable tagged union defaulting to `null` for source
compatibility with existing event producers. Its variants are:

- `graph: { node_entity, x, y }`: the resolved graph destination.
- `direct: { x, y }`: the resolved direct destination.
- `grid: { col, row, x, y }`: the resolved goal cell and its world position.

The updated controller always supplies a non-null destination for all three
modes, including redundant already-there arrivals and rehydrated walks.
For grid and off-graph direct arrivals, the legacy `node_entity` remains
zero, matching the existing off-graph convention; graph arrivals preserve
its existing meaning. New consumers switch on `destination`; old consumers
can keep reading the original fields. A legacy producer that omits the new
field yields `null`, which consumers must handle. Do not reinterpret zero
as a grid cell id. Declare the union inline in `Events.arrived` and verify
assembler discovery and generated event payloads before implementation ships.

### Event integration

Use Labelle's typed plugin events for sparse state transitions: arrival,
navigation failure and committed grid changes. Route emissions through the
controller's existing guarded `emitGameEvent` helper, so builds without a
subscriber still work. The defaulted destination field must also work with
that helper's payload construction.

Game handlers for construction, demolition or terrain changes can call
`refreshFootprint` after changing an entity. Coalesce those notifications
into dirty regions rather than rebuilding once per incoming event. The
pathfinder must not depend on any particular game's job or building event
names. Component add/remove/change notifications could eventually replace
the footprint set scan, but their availability, plugin subscription wiring
and delivery ordering must first be verified against the target engine.
Entity creation/destruction hooks alone do not cover component changes or
position edits. Keep the set scan and explicit refresh contract until that
coverage is proven; cache old footprints for removal notifications.

Apply re-stamping, region relabelling and affected-route re-planning inside
the controller before advancing movement. Publish `grid_changed` after
that update is committed; consumers must not observe a new grid with stale
routes. Internal invalidation must work even when no game subscribes to the
event. Events are notifications, while queries read the current state; a
buffered event's epoch lets a consumer recognize that later updates have
already superseded its bounds. Do not emit per-cell or per-frame movement
events, or replace immediate command acceptance with asynchronous requests.

### Keeping the grid current

`Controller.advance` already detects node-set changes by counting. The grid
does the same for footprints:

1. Each advance, compare the set of entities carrying `NavObstacle` or
   `NavCost` with the set stamped last time.
2. For each added or removed entity, re-stamp only the cells under its
   rectangle, from the footprints that still overlap those cells.
3. If anything changed: relabel regions, bump the epoch and emit
   `pathfinder__grid_changed`. Before advancing movement, re-plan every
   affected walk using the segment dependency rule below.

Invalidation checks every remaining segment, starting at the agent's current
position and continuing through all remaining waypoints. It must not check
only waypoint positions: a new obstacle can lie between two distant smoothed
waypoints. Each segment depends on every cell its traversal touches, plus
both orthogonal support cells at each diagonal transition. A change to any
of these cells triggers re-planning, even if neither endpoint nor a directly
traversed cell changed. Cost changes use the same dependency set.

Use the same conservative cell traversal for search validation, smoothing
and invalidation. A rectangle test may be a broad-phase filter, but it must
include diagonal support cells; expanding changed bounds by one cell is a
safe conservative filter. Clamp expanded bounds to the grid. The event's
rectangle still describes the actual re-stamped area, not this expansion.
On footprint refresh, dirty both the cached old footprint and the new one;
on removal, use the cached footprint because ECS data may already be gone.
Coalesce changes before re-planning and never move an agent along a segment
invalidated by the applied grid update.

An entity that moves or resizes without being added or removed is not
detected; the game calls `refreshFootprint`. That keeps the per-frame check to
a set comparison.

### Search

- 8-connected grid. A diagonal step is allowed only when both cells it passes
  between are free, so paths never cut a corner.
- Step cost is the entered cell's cost, times 14/10 for diagonals.
- Heuristic: octile distance times the lowest cost on the grid, which keeps it
  admissible with weighted cells.
- The goal is a set of cells. For `navigateAdjacent` it is every free cell
  bordering the target's blocked cells; the heuristic measures to the set's
  bounding box.
- Neighbours are implicit, computed from the cell index. The existing
  `algo.AStar` stores nodes, positions and edges explicitly, which for a grid
  means eight stored edges per cell, so this RFC adds a dedicated
  `algo.GridAStar` rather than feeding the grid to it.

### Path smoothing

A raw grid path moves in 45° steps. After the search, waypoints are dropped
while the straight segment between their neighbours crosses only free cells
and costs no more than the cells it replaces. The second condition stops
smoothing from dragging a path back through expensive terrain the search
deliberately went around.

The traversal is conservative (supercover): a segment passing exactly through
a grid corner checks both side cells as well as the diagonal destination.
Smoothing must preserve the search's no-corner-cutting rule. Keep or recompute
the traversed and diagonal support cells for every retained segment so later
grid changes invalidate the smoothed route correctly.

### Regions

Every free cell carries the id of its connected component, found by flood
fill with the same no-corner-cutting rule as the search. v1 relabels the whole
grid after a change: linear in the cell count, and cheap for the grid sizes
this RFC targets (up to roughly 256x256). Incremental relabelling can come
later behind the same queries.

### Persistence

`Navigating` gains a third mode:

```zig
pub const Mode = enum { graph, direct, grid };
```

For a grid walk, `target_x` / `target_y` hold the world position of the goal
cell that was chosen, including for `navigateAdjacent`. On load the existing
rehydration sweep re-issues the walk to that position. This keeps the current
rule that persisted targets are positions, never entity references. If the
loaded map no longer allows it, the walk fails with `navigation_failed` and
the game decides what to do.

### Debug drawing

A gizmo category draws blocked cells, cell costs, region ids and each active
path, using the plugin's existing `GizmoCategories`.

## Integration with labelle-engine

- The three components are discovered like the plugin's current ones.
- `pathfinder__grid_changed` and the extended arrival payload are declared
  inline in `src/root.zig`, where the assembler looks for plugin events.
- The game keeps its single driver script calling `Controller.advance`.
- No new engine API is required as far as this draft has checked; that needs
  confirming against the engine version the plugin targets.

## Backwards compatibility

Additive. A scene without a `NavGrid` entity never builds a grid, and every
existing command, query and component behaves as in 4.2. The arrival event
retains its original fields and adds a defaulted optional destination; existing
producers may omit it and existing consumers may ignore it. `Navigating`
gains an enum value; saves written by 4.2 contain only `graph` and `direct`
and load unchanged.

## Implementation plan

1. `algo.GridAStar` and the grid type (blocked, cost, world/cell mapping),
   with tests. No ECS.
2. Region labelling and the reachability queries, with tests.
3. `NavGrid`, `NavObstacle`, `NavCost`; building the grid at setup; the gizmo
   layer.
4. `navigateTo` wired to the existing walker; `Navigating.Mode.grid`;
   save/load rehydration; explicit arrival destinations for all modes and
   compatibility checks for old event producers and consumers.
5. `navigateAdjacent` and multi-goal search.
6. Change detection, partial re-stamping, re-planning of affected walks,
   `pathfinder__grid_changed`. Verify an obstacle between unchanged waypoints
   invalidates a route, a blocked diagonal support cell invalidates a diagonal,
   and an unrelated change leaves an unaffected route alone.
7. Path smoothing, with corner-crossing and post-smoothing invalidation checks.
8. Long Snow as the reference consumer: keyboard collision from the same
   grid, click to walk, then "fell this tree".

Steps 1 to 4 are enough to walk around obstacles on a static map.

## Alternatives considered

1. **Generate `MovementNode`s on a lattice and keep the graph mode.**
   No new search code, and it reuses everything. But Floyd-Warshall is cubic
   in the node count and is rebuilt on every change, so it only works for
   coarse lattices on small maps, and coarse lattices give poor paths.
2. **Navigation mesh.** Better paths with fewer nodes, but rebuilding a mesh
   as obstacles come and go is much more work than re-stamping cells, and
   per-cell terrain cost does not map onto it naturally.
3. **Steering only, no global path.** Fine around isolated trees, but agents
   get stuck behind anything concave, such as a building.
4. **A separate plugin.** Keeps this package smaller, but duplicates the
   walker, the persisted order and the events, and a game with both indoor
   graphs and outdoor ground would need two plugins to agree on who is moving
   an entity.

## Open questions

1. **One command or two?** Should `navigate` pick the navigation mode itself (grid
   when the scene has a `NavGrid`, graph otherwise), instead of adding
   `navigateTo`? A game that mixes both modes needs a rule for which one
   answers.
2. **Agent size.** One `agent_radius` per grid is simple but wrong once agents
   differ in size. Per-agent clearance needs a clearance map.
3. **Footprint shape.** Are rectangles enough, or do circles and multi-cell
   masks belong in v1?
4. **Overlapping `NavCost`.** "Last stamped wins" depends on entity order. A
   priority field, or the maximum, would be deterministic.
5. **Search budget.** v1 searches synchronously inside the command. At what
   grid size does that need a per-frame expansion budget and `deferred`
   results?
6. **Who owns keyboard collision?** The grid can answer `isBlocked`, but a
   directly controlled character probably wants sliding along walls, which is
   not pathfinding.
