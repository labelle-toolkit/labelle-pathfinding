# Labelle Pathfinding

A pathfinding library for Zig game development. Part of the [labelle-toolkit](https://github.com/labelle-toolkit), it provides a self-contained pathfinding engine, spatial indexing, and shortest path algorithms.

## Features

- **PathfindingEngine** - Self-contained engine that owns entity positions, with callbacks and spatial queries
- **Simplified Config** - Use `PathfindingEngineSimple(Entity, Context)` for quick setup
- **Grid Helper** - `createGrid()` for easy grid-based pathfinding with coordinate utilities
- **Vec2 Positions** - Returns `Vec2` from zig-utils for ecosystem compatibility
- **QuadTree** - Spatial partitioning for O(log n) entity and node lookups
- **Floyd-Warshall Algorithm** - All-pairs shortest path computation with SIMD and parallel optimizations (5-16x faster)
- **A\* Algorithm** - Single-source shortest path with multiple heuristics
- **Connection Modes** - Omnidirectional (top-down), directional (platformer), and building (vertical via stairs) graph building
- **Stair Traffic Control** - Multi-lane, directional, or single-file stair usage with waiting areas

## Requirements

- Zig 0.15.2 or later

## Installation

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .pathfinding = .{
        .url = "https://github.com/labelle-toolkit/labelle-pathfinding/archive/refs/tags/v2.5.0.tar.gz",
        .hash = "...",
    },
},
```

Or use `zig fetch`:

```bash
zig fetch --save https://github.com/labelle-toolkit/labelle-pathfinding/archive/refs/tags/v2.5.0.tar.gz
```

Then in your `build.zig`:

```zig
const pathfinding = b.dependency("pathfinding", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("pathfinding", pathfinding.module("pathfinding"));
```

## Usage

### PathfindingEngine (Recommended)

The PathfindingEngine is a complete solution that manages entity positions internally. The game queries the engine for positions rather than owning them.

```zig
const std = @import("std");
const pathfinding = @import("pathfinding");

// Simple configuration with direct types
const Engine = pathfinding.PathfindingEngineSimple(u64, *Game);

// Or use full config for advanced options
const Config = struct {
    pub const Entity = u64;
    pub const Context = *Game;
    // Optional: configure log verbosity (defaults to .none)
    pub const log_level: pathfinding.LogLevel = .info;
};
const EngineWithLogging = pathfinding.PathfindingEngine(Config);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var game = Game{};
    var engine = try Engine.init(allocator);
    defer engine.deinit();

    // Build the node graph
    try engine.addNode(0, 0, 0);      // node 0 at (0, 0)
    try engine.addNode(1, 100, 0);    // node 1 at (100, 0)
    try engine.addNode(2, 200, 0);    // node 2 at (200, 0)

    // Auto-connect nodes within distance
    try engine.connectNodes(.{
        .omnidirectional = .{ .max_distance = 150, .max_connections = 4 },
    });
    try engine.rebuildPaths();

    // Register entity (engine owns position)
    try engine.registerEntity(player_id, 0, 0, 100.0);  // at (0,0), speed 100

    // Request path
    try engine.requestPath(player_id, 2);  // move to node 2

    // Game loop
    while (engine.isMoving(player_id)) {
        engine.tick(&game, delta_time);

        // Query position for rendering
        if (engine.getPosition(player_id)) |pos| {
            draw(pos.x, pos.y);
        }
    }

    // Spatial queries for combat/AI
    var nearby: [10]u64 = undefined;
    const enemies = engine.getEntitiesInRadius(x, y, attack_range, &nearby);
}
```

### Grid Helper

For grid-based games, use `createGrid` to set up nodes and connections in one call:

```zig
// Create an 8x8 grid with 4-directional movement
const grid = try engine.createGrid(.{
    .rows = 8,
    .cols = 8,
    .cell_size = 60.0,
    .offset_x = 100,
    .offset_y = 60,
    .connection = .four_way,  // or .eight_way for diagonals
});
try engine.rebuildPaths();

// Use grid helpers for coordinate conversion
const pos = grid.toScreen(3, 4);      // grid coords -> Vec2 screen position
const node_id = grid.toNodeId(3, 4);  // grid coords -> node ID
const coords = grid.fromNodeId(42);   // node ID -> {col, row}
const node_pos = grid.nodePosition(42); // node ID -> Vec2 position
```

### Connection Convenience Functions

Simplified grid connection setup:

```zig
// Instead of:
try engine.connectNodes(.{ .omnidirectional = .{ .max_distance = cell_size * 1.1, .max_connections = 4 } });

// Use:
try engine.connectAsGrid4(cell_size);  // 4-directional (up/down/left/right)
try engine.connectAsGrid8(cell_size);  // 8-directional (including diagonals)
```

### Vec2 Position Type

Position queries return `Vec2` from zig-utils for ecosystem compatibility:

```zig
if (engine.getPosition(entity)) |pos| {
    // pos is Vec2 with useful methods
    const dist = pos.distance(target);
    const normalized = pos.normalize();
}

// Vec2 convenience methods for adding nodes
try engine.addNodeVec2(id, Vec2{ .x = 100, .y = 200 });
try engine.registerEntityVec2(entity, pos, speed);
```

### Log Levels

Control logging verbosity via the Config struct:

```zig
const Config = struct {
    pub const Entity = u64;
    pub const Context = *Game;
    pub const log_level: pathfinding.LogLevel = .debug;  // verbose logging
};
```

| Level | Description |
|-------|-------------|
| `.none` | Disable all logging (default) |
| `.err` | Critical failures only |
| `.warning` | Recoverable errors (e.g., entity not found, no path exists) |
| `.info` | Path requests, entity registration/unregistration, graph rebuilds |
| `.debug` | Detailed: path steps, stair queue operations, spatial updates |

Logs use Zig's `std.log` scoped to `.pathfinding`, so they integrate with your application's log configuration.

### Callbacks

```zig
fn onNodeReached(game: *Game, entity: u64, node: u32) void {
    // Entity reached a waypoint
}

fn onPathCompleted(game: *Game, entity: u64, node: u32) void {
    // Entity finished its path
}

fn onPathBlocked(game: *Game, entity: u64, node: u32) void {
    // No path available to target node
}

// Set callbacks
engine.on_node_reached = onNodeReached;
engine.on_path_completed = onPathCompleted;
engine.on_path_blocked = onPathBlocked;
```

### Directional Connections (Platformers)

```zig
// For platformer-style movement (left/right/up/down only)
try engine.connectNodes(.{
    .directional = .{
        .horizontal_range = 60,  // connect horizontally within 60 units
        .vertical_range = 60,    // connect vertically within 60 units (ladders)
    },
});

// Query directional edges
if (engine.getDirectionalEdges(node_id)) |edges| {
    if (edges.left) |left_node| { /* can go left */ }
    if (edges.right) |right_node| { /* can go right */ }
    if (edges.up) |up_node| { /* can climb up */ }
    if (edges.down) |down_node| { /* can go down */ }
}

// Add one-way edges (e.g., drop-downs)
try engine.addEdge(top_node, bottom_node, false);  // one-way
```

### Building Mode with Stairs

For 2D building games where vertical movement is only allowed via stair nodes:

```zig
// Add nodes with stair modes
try engine.addNode(0, 0, 0);    // regular floor node
try engine.addNode(1, 100, 0);  // regular floor node
try engine.addNode(2, 100, 100);  // regular upper floor node

// Mark nodes as stairs with traffic control
try engine.setStairMode(1, .single);     // single-file stair at ground
try engine.setStairMode(2, .single);     // single-file stair at upper floor

// Connect with building mode (horizontal + vertical via stairs only)
try engine.connectNodes(.{
    .building = .{
        .horizontal_range = 60,
        .vertical_range = 120,
    },
});
try engine.rebuildPaths();
```

#### Stair Modes

| Mode | Description |
|------|-------------|
| `.none` | Not a stair - no vertical connections (default) |
| `.all` | Multi-lane stair - unlimited concurrent usage |
| `.direction` | Directional stair - multiple entities same direction only |
| `.single` | Single-file stair - only one entity at a time |

#### Waiting Areas

When stairs are busy, entities wait at designated spots instead of stacking:

```zig
// Define waiting area for a stair
try engine.setWaitingArea(stair_node_id, &[_]pathfinding.Position{
    .{ .x = 80, .y = 0 },   // waiting spot 1
    .{ .x = 60, .y = 0 },   // waiting spot 2
    .{ .x = 40, .y = 0 },   // waiting spot 3
});

// Check if entity is waiting
if (engine.getPosition(entity)) |pos| {
    if (pos.waiting_for_stair) |stair_id| {
        // Entity is waiting to use this stair
    }
}
```

### Floyd-Warshall (Direct Usage)

Best for dense graphs or when you need paths between many node pairs.

```zig
var fw = pathfinding.FloydWarshall.init(allocator);
defer fw.deinit();

fw.resize(10);
try fw.clean();

// Add edges between entities (using entity IDs)
fw.addEdgeWithMapping(100, 200, 1);
fw.addEdgeWithMapping(200, 300, 1);

// Compute all shortest paths
fw.generate();

// Query paths
const dist = fw.valueWithMapping(100, 300);  // Returns 2
const next = fw.nextWithMapping(100, 300);   // Returns 200
```

#### Optimized Variants

For performance-critical applications, use the optimized implementations:

```zig
// SIMD-optimized (5-8x faster, single-threaded)
var fw = pathfinding.FloydWarshallSimd.init(allocator);

// Parallel + SIMD (up to 16x faster, multi-threaded)
var fw = pathfinding.FloydWarshallParallel.init(allocator);
```

The optimized variants have the same API as the legacy implementation. Use `FloydWarshallParallel` for graphs with 256+ nodes where multi-threading provides the most benefit.

You can also configure PathfindingEngine to use an optimized variant:

```zig
const Config = struct {
    pub const Entity = u64;
    pub const Context = *Game;
    pub const floyd_warshall_variant: pathfinding.FloydWarshallVariant = .optimized_parallel;
};
```

| Variant | Description | Best For |
|---------|-------------|----------|
| `.legacy` | Original ArrayList-based (default) | Backward compatibility |
| `.optimized_simd` | Flat memory + SIMD vectorization | Small-medium graphs, single-threaded |
| `.optimized_parallel` | SIMD + multi-threading | Large graphs (256+ nodes) |

Run the benchmark to see performance on your hardware:

```bash
zig build run-benchmark
```

### A* Algorithm (Direct Usage)

Best for single-source queries in large sparse graphs.

```zig
var astar = pathfinding.AStar.init(allocator);
defer astar.deinit();

astar.resize(10);
try astar.clean();
astar.setHeuristic(.manhattan);

// Set node positions for heuristic
try astar.setNodePositionWithMapping(100, .{ .x = 0, .y = 0 });
try astar.setNodePositionWithMapping(200, .{ .x = 10, .y = 0 });

// Add edges
astar.addEdgeWithMapping(100, 200, 1);

// Find path
var path = std.ArrayList(u32).init(allocator);
defer path.deinit();

if (try astar.findPathWithMapping(100, 200, &path)) |cost| {
    // path.items contains the route
}
```

## Algorithm Selection Guide

| Use Case | Recommended |
|----------|-------------|
| Game with entities moving on waypoints | **PathfindingEngine** |
| Need spatial queries (radius, rectangle) | **PathfindingEngine** |
| Many queries between different node pairs | Floyd-Warshall |
| Dense graphs (many edges) | Floyd-Warshall |
| Single source-destination queries | A* |
| Large sparse graphs | A* |
| Dynamic graphs that change frequently | A* |

## API Reference

### PathfindingEngine

| Method | Description |
|--------|-------------|
| `init(allocator)` | Create engine instance |
| `deinit()` | Free resources |
| `addNode(id, x, y)` | Add a waypoint node |
| `addNodeVec2(id, pos)` | Add node with Vec2 position |
| `addNodeAuto(x, y)` | Add node with auto-generated ID |
| `removeNode(id)` | Remove a node |
| `createGrid(config)` | Create grid of nodes with connections |
| `connectNodes(mode)` | Auto-connect nodes |
| `connectAsGrid4(cell_size)` | Connect as 4-directional grid |
| `connectAsGrid8(cell_size)` | Connect as 8-directional grid |
| `addEdge(from, to, bidirectional)` | Manually add edge |
| `rebuildPaths()` | Recompute Floyd-Warshall paths |
| `registerEntity(id, x, y, speed)` | Register entity at position |
| `registerEntityVec2(id, pos, speed)` | Register entity with Vec2 |
| `unregisterEntity(id)` | Remove entity |
| `requestPath(entity, target_node)` | Start pathfinding |
| `cancelPath(entity)` | Stop movement |
| `tick(ctx, delta)` | Update all entities |
| `getPosition(entity)` | Get entity position (returns Vec2) |
| `getNodePosition(node)` | Get node position (returns Vec2) |
| `getSpeed(entity)` | Get entity speed |
| `setSpeed(entity, speed)` | Set entity speed |
| `isMoving(entity)` | Check if entity is moving |
| `getCurrentNode(entity)` | Get entity's current node |
| `getEntitiesInRadius(x, y, r, buf)` | Spatial query |
| `getEntitiesInRect(x, y, w, h, buf)` | Rectangle query |
| `getNodesInRadius(x, y, r, buf)` | Find nearby nodes |
| `setStairMode(node, mode)` | Set stair traffic mode |
| `getStairMode(node)` | Get stair traffic mode |
| `setWaitingArea(node, spots)` | Define waiting area for stair |
| `getStairState(node)` | Get runtime stair traffic state |

### Grid Helper

| Method | Description |
|--------|-------------|
| `toScreen(col, row)` | Convert grid coords to Vec2 position |
| `toNodeId(col, row)` | Convert grid coords to node ID |
| `fromNodeId(node_id)` | Convert node ID to {col, row} |
| `nodePosition(node_id)` | Get Vec2 position for node ID |
| `isValid(col, row)` | Check if grid coords are in bounds |
| `nodeCount()` | Get total number of nodes in grid |

### Heuristics

| Heuristic | Best For |
|-----------|----------|
| `euclidean` | Any-angle movement (default) |
| `manhattan` | 4-directional grid movement |
| `chebyshev` | 8-directional with equal diagonal cost |
| `octile` | 8-directional with sqrt(2) diagonal cost |
| `zero` | Dijkstra's algorithm (no heuristic) |

## Running Examples

```bash
# Basic example (start here)
zig build run-basic

# Game integration with callbacks
zig build run-game

# Platformer with directional connections
zig build run-platformer

# Full engine features
zig build run-engine

# Building with multi-floor stairs
zig build run-building

# Run all examples
zig build run-examples
```

## Running Tests

```bash
# Run built-in unit tests
zig build test

# Run zspec tests
zig build spec
```

## License

MIT
