# Labelle Pathfinding

A pathfinding library for Zig game development. Part of the [labelle-toolkit](https://github.com/labelle-toolkit), it provides node-based movement systems and shortest path algorithms with direct zig-ecs integration.

## Features

- **Floyd-Warshall Algorithm** - All-pairs shortest path computation with entity ID mapping
- **A\* Algorithm** - Single-source shortest path with multiple heuristics (Euclidean, Manhattan, Chebyshev, Octile)
- **zig-ecs Integration** - Direct integration with [zig-ecs](https://github.com/prime31/zig-ecs) Registry
- **Movement Node Components** - ECS-ready components for node-based movement
- **Registry-based Controller** - Find closest movement nodes using ECS queries
- **Entity ID Mapping** - Seamless integration with ECS entity identifiers

## Requirements

- Zig 0.15.1 or later

## Installation

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .pathfinding = .{
        .url = "https://github.com/labelle-toolkit/labelle-pathfinding/archive/refs/tags/v1.0.0.tar.gz",
        .hash = "...",
    },
},
```

Or use `zig fetch`:

```bash
zig fetch --save https://github.com/labelle-toolkit/labelle-pathfinding/archive/refs/tags/v1.0.0.tar.gz
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

### Floyd-Warshall Shortest Paths

Best for dense graphs or when you need paths between many node pairs.

```zig
const pathfinding = @import("pathfinding");
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var fw = pathfinding.FloydWarshall.init(allocator);
    defer fw.deinit();

    fw.resize(10);
    try fw.clean();

    // Add edges between entities (using entity IDs)
    fw.addEdgeWithMapping(100, 200, 1);  // entity 100 -> 200, weight 1
    fw.addEdgeWithMapping(200, 300, 1);  // entity 200 -> 300, weight 1
    fw.addEdgeWithMapping(300, 400, 1);  // entity 300 -> 400, weight 1

    // Compute all shortest paths
    fw.generate();

    // Query paths
    if (fw.hasPathWithMapping(100, 400)) {
        const dist = fw.valueWithMapping(100, 400);  // Returns 3
        const next = fw.nextWithMapping(100, 400);   // Returns 200
    }
}
```

### A* Algorithm

Best for single-source queries in large sparse graphs.

```zig
const pathfinding = @import("pathfinding");
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var astar = pathfinding.AStar.init(allocator);
    defer astar.deinit();

    astar.resize(10);
    try astar.clean();

    // Set heuristic (euclidean, manhattan, chebyshev, octile, zero)
    astar.setHeuristic(.manhattan);

    // Set node positions for heuristic calculation
    try astar.setNodePositionWithMapping(100, .{ .x = 0, .y = 0 });
    try astar.setNodePositionWithMapping(200, .{ .x = 10, .y = 0 });
    try astar.setNodePositionWithMapping(300, .{ .x = 10, .y = 10 });

    // Add edges
    astar.addEdgeWithMapping(100, 200, 1);
    astar.addEdgeWithMapping(200, 300, 1);

    // Find path (computed on-demand)
    var path = std.ArrayList(u32).init(allocator);
    defer path.deinit();

    if (try astar.findPathWithMapping(100, 300, &path)) |cost| {
        // cost = 2, path.items = [100, 200, 300]
    }
}
```

### ECS Integration with zig-ecs

```zig
const pathfinding = @import("pathfinding");
const std = @import("std");

pub fn main() !void {
    var registry = pathfinding.Registry.init(std.heap.page_allocator);
    defer registry.deinit();

    // Create movement nodes
    const node1 = registry.create();
    registry.add(node1, pathfinding.MovementNode{});
    registry.add(node1, pathfinding.Position{ .x = 0, .y = 0 });

    const node2 = registry.create();
    registry.add(node2, pathfinding.MovementNode{ .right_entt = node1 });
    registry.add(node2, pathfinding.Position{ .x = 10, .y = 0 });

    // Find closest node to a position
    const closest = try pathfinding.MovementNodeController.getClosestMovementNode(
        &registry,
        .{ .x = 5, .y = 0 },
    );

    // Get closest node with distance
    const result = try pathfinding.MovementNodeController.getClosestMovementNodeWithDistance(
        &registry,
        .{ .x = 5, .y = 0 },
    );
    // result.node_entt = closest entity, result.distance = distance to it

    // Batch update all entities tracking their closest node
    pathfinding.MovementNodeController.updateAllClosestNodes(&registry);
}
```

### Movement Components

```zig
const pathfinding = @import("pathfinding");

// Movement node with directional links
const node = pathfinding.MovementNode{
    .left_entt = entity1,
    .right_entt = entity2,
    .up_entt = entity3,
    .down_entt = entity4,
};

// Track closest node to an entity
const closest = pathfinding.ClosestMovementNode{
    .node_entt = some_entity,
    .distance = 10.5,
};

// Entity moving towards a target
const moving = pathfinding.MovingTowards{
    .target_x = 100.0,
    .target_y = 200.0,
    .closest_node_entt = some_entity,
    .speed = 15.0,
};

// Manage a path through nodes
var path = pathfinding.WithPath.init(allocator);
defer path.deinit();

try path.append(entity1);
try path.append(entity2);
const next = path.popFront();  // Returns entity1
```

### Distance Calculations

```zig
const pathfinding = @import("pathfinding");

const a = pathfinding.Position{ .x = 0, .y = 0 };
const b = pathfinding.Position{ .x = 3, .y = 4 };

const dist = pathfinding.distance(a, b);      // Returns 5.0
const distSqr = pathfinding.distanceSqr(a, b); // Returns 25.0 (faster)
```

## Algorithm Selection Guide

| Use Case | Recommended Algorithm |
|----------|----------------------|
| Many queries between different node pairs | Floyd-Warshall |
| Dense graphs (many edges) | Floyd-Warshall |
| Static graphs that don't change | Floyd-Warshall |
| Single source-destination queries | A* |
| Large sparse graphs | A* |
| Dynamic graphs that change frequently | A* |
| Real-time pathfinding | A* |

## API Reference

### FloydWarshall

| Method | Description |
|--------|-------------|
| `init(allocator)` | Create a new instance |
| `deinit()` | Free resources |
| `resize(size)` | Set the maximum number of vertices |
| `clean()` | Reset and initialize the graph |
| `addEdge(u, v, weight)` | Add edge using direct indices |
| `addEdgeWithMapping(u, v, weight)` | Add edge using entity IDs |
| `generate()` | Compute all shortest paths |
| `hasPath(u, v)` / `hasPathWithMapping(u, v)` | Check if path exists |
| `value(u, v)` / `valueWithMapping(u, v)` | Get distance |
| `setPathWithMapping(path, u, v)` | Reconstruct path into ArrayList |
| `nextWithMapping(u, v)` | Get next hop in path |

### AStar

| Method | Description |
|--------|-------------|
| `init(allocator)` | Create a new instance |
| `deinit()` | Free resources |
| `resize(size)` | Set the maximum number of vertices |
| `clean()` | Reset and initialize the graph |
| `setHeuristic(heuristic)` | Set heuristic function |
| `setNodePosition(idx, pos)` | Set node position for heuristic |
| `addEdge(u, v, weight)` | Add edge using direct indices |
| `addEdgeWithMapping(u, v, weight)` | Add edge using entity IDs |
| `findPath(start, goal, path)` | Find shortest path |
| `findPathWithMapping(start, goal, path)` | Find path using entity IDs |

### MovementNodeController

| Method | Description |
|--------|-------------|
| `getClosestMovementNode(registry, pos)` | Find nearest movement node entity |
| `getClosestMovementNodeWithDistance(registry, pos)` | Find nearest node with distance |
| `updateAllClosestNodes(registry)` | Batch update all ClosestMovementNode components |

### Components

| Component | Description |
|-----------|-------------|
| `MovementNode` | Node with 4-directional links (left, right, up, down) |
| `ClosestMovementNode` | Tracks closest node entity and distance |
| `MovingTowards` | Entity movement target and speed |
| `WithPath` | Managed path through movement nodes |

### Heuristics

| Heuristic | Best For |
|-----------|----------|
| `euclidean` | Any-angle movement (default) |
| `manhattan` | 4-directional grid movement |
| `chebyshev` | 8-directional with equal diagonal cost |
| `octile` | 8-directional with sqrt(2) diagonal cost |
| `zero` | Dijkstra's algorithm (no heuristic) |

### Types

| Type | Description |
|------|-------------|
| `Position` | 2D coordinates (re-exported from zig-utils Vector2) |
| `Entity` | ECS entity type (re-exported from zig-ecs) |
| `Registry` | ECS registry (re-exported from zig-ecs) |

## Running Tests

```bash
# Run built-in unit tests
zig build test

# Run zspec tests
zig build spec

# Run usage examples
zig build run-examples
```

## License

MIT
