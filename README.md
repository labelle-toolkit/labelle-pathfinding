# Labelle Pathfinding

A pathfinding library for Zig game development. Part of the [labelle-toolkit](https://github.com/labelle-toolkit), it provides node-based movement systems and shortest path algorithms optimized for ECS integration.

## Features

- **Floyd-Warshall Algorithm** - All-pairs shortest path computation with entity ID mapping
- **Movement Node Components** - ECS-ready components for node-based movement
- **Spatial Query Controller** - Find closest movement nodes using quad tree queries
- **Entity ID Mapping** - Seamless integration with ECS entity identifiers
- **Labelle Integration** - Uses `labelle.Position` for coordinates

## Requirements

- Zig 0.15.1 or later

## Installation

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .pathfinding = .{
        .url = "https://github.com/labelle-toolkit/labelle-pathfinding/archive/refs/heads/main.tar.gz",
        .hash = "...",
    },
},
```

Or use `zig fetch`:

```bash
zig fetch --save https://github.com/labelle-toolkit/labelle-pathfinding/archive/refs/heads/main.tar.gz
```

Then in your `build.zig`:

```zig
const pathfinding = b.dependency("pathfinding", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("pathfinding", pathfinding.module("pathfinding"));
```

Note: This library depends on [labelle](https://github.com/labelle-toolkit/labelle), which is automatically included as a transitive dependency.

## Usage

### Floyd-Warshall Shortest Paths

```zig
const pathfinding = @import("pathfinding");
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a distance graph
    var fw = pathfinding.FloydWarshall.init(allocator);
    defer fw.deinit();

    // Set graph size and initialize
    fw.resize(10);
    try fw.clean();

    // Add edges between entities (using entity IDs)
    fw.addEdgeWithMapping(100, 200, 1);  // entity 100 -> 200, weight 1
    fw.addEdgeWithMapping(200, 300, 1);  // entity 200 -> 300, weight 1
    fw.addEdgeWithMapping(300, 400, 1);  // entity 300 -> 400, weight 1

    // Compute all shortest paths
    fw.generate();

    // Check if path exists
    if (fw.hasPathWithMapping(100, 400)) {
        // Get the distance
        const dist = fw.valueWithMapping(100, 400);
        std.debug.print("Distance: {}\n", .{dist});

        // Reconstruct the path
        var path = std.ArrayList(u32).init(allocator);
        defer path.deinit();
        try fw.setPathWithMapping(&path, 100, 400);
        // path.items contains: [100, 200, 300, 400]
    }
}
```

### Movement Components

```zig
const pathfinding = @import("pathfinding");

// Create a movement node with directional links
const node = pathfinding.MovementNode{
    .left_entt = 1,
    .right_entt = 2,
    .up_entt = 3,
    .down_entt = 4,
};

// Track closest node to an entity
const closest = pathfinding.ClosestMovementNode{
    .node_entt = 5,
    .distance = 10.5,
};

// Entity moving towards a target
const moving = pathfinding.MovingTowards{
    .target_x = 100.0,
    .target_y = 200.0,
    .closest_node_entt = 5,
    .speed = 15.0,
};

// Manage a path through nodes
var path = pathfinding.WithPath.init(allocator);
defer path.deinit();

try path.append(1);
try path.append(2);
try path.append(3);

const next_node = path.popFront();  // Returns 1
```

### Movement Node Controller

```zig
const pathfinding = @import("pathfinding");
const labelle = @import("labelle");
const std = @import("std");

// Define your quad tree type that implements queryOnBuffer
const MyQuadTree = struct {
    // ... your implementation

    pub fn queryOnBuffer(
        self: *MyQuadTree,
        rect: pathfinding.Rectangle,
        buffer: *std.ArrayList(pathfinding.EntityPosition),
    ) !void {
        // Query spatial index and populate buffer
    }
};

// Create a controller for your quad tree type
const Controller = pathfinding.MovementNodeController(MyQuadTree);

// Find closest movement node to a position (using labelle.Position)
var quad_tree: MyQuadTree = .{};
const pos = labelle.Position{ .x = 50.0, .y = 75.0 };

const closest = try Controller.getClosestMovementNode(
    &quad_tree,
    pos,
    allocator,
);
// closest.entity contains the entity ID of the nearest movement node
```

### Distance Calculations

```zig
const pathfinding = @import("pathfinding");
const labelle = @import("labelle");

const a = labelle.Position{ .x = 0, .y = 0 };
const b = labelle.Position{ .x = 3, .y = 4 };

// Calculate euclidean distance
const dist = pathfinding.distance(a, b);  // Returns 5.0

// Calculate squared distance (faster, no sqrt)
const distSqr = pathfinding.distanceSqr(a, b);  // Returns 25.0
```

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
| `hasPath(u, v)` | Check if path exists (direct indices) |
| `hasPathWithMapping(u, v)` | Check if path exists (entity IDs) |
| `value(u, v)` | Get distance (direct indices) |
| `valueWithMapping(u, v)` | Get distance (entity IDs) |
| `setPathWithMapping(path, u, v)` | Reconstruct path into ArrayList |
| `nextWithMapping(u, v)` | Get next hop in path |

### Components

| Component | Description |
|-----------|-------------|
| `MovementNode` | Node with 4-directional links (left, right, up, down) |
| `ClosestMovementNode` | Tracks closest node to an entity |
| `MovingTowards` | Entity movement target and speed |
| `WithPath` | Managed path through movement nodes |

### MovementNodeController

| Method | Description |
|--------|-------------|
| `getClosestMovementNode(quad_tree, position, allocator)` | Find nearest node |
| `getClosestMovementNodeWithBuffer(quad_tree, position, buffer)` | Find nearest node using provided buffer |

### Utility Functions and Types

| Name | Description |
|------|-------------|
| `Position` | Re-exported from `labelle.Position` - 2D coordinates with x, y fields |
| `distance(a, b)` | Calculate euclidean distance between two positions |
| `distanceSqr(a, b)` | Calculate squared distance (faster, avoids sqrt) |
| `Rectangle` | Rectangular region for spatial queries |
| `EntityPosition` | Position with associated entity ID |

## Running Tests

```bash
# Run built-in unit tests
zig build test

# Run zspec tests
zig build spec
```

## Related Projects

- [labelle](https://github.com/labelle-toolkit/labelle) - 2D graphics library for Zig games

## License

MIT
