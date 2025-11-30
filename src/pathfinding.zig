//! Labelle Pathfinding
//!
//! A pathfinding library for Zig game development.
//! Part of the labelle-toolkit, integrates with zig-ecs for ECS support.
//! Provides node-based movement systems and shortest path algorithms.
//!
//! ## Features
//! - Floyd-Warshall all-pairs shortest path algorithm
//! - A* single-source shortest path algorithm with multiple heuristics
//! - Movement node components for zig-ecs
//! - Registry-based controller for finding closest nodes
//! - Entity ID mapping for ECS integration
//!
//! ## Algorithm Selection Guide
//! - **A***: Best for single-source queries, large sparse graphs, real-time games
//! - **Floyd-Warshall**: Best when you need all-pairs paths, dense graphs, or
//!   when paths are queried repeatedly between many node pairs
//!
//! ## Example (ECS Integration)
//! ```zig
//! const pathfinding = @import("pathfinding");
//! const ecs = @import("zig_ecs");
//!
//! var registry = ecs.Registry.init(allocator);
//! defer registry.deinit();
//!
//! // Create movement nodes
//! const node1 = registry.create();
//! registry.add(node1, pathfinding.MovementNode{});
//! registry.add(node1, pathfinding.Position{ .x = 0, .y = 0 });
//!
//! const node2 = registry.create();
//! registry.add(node2, pathfinding.MovementNode{ .right_entt = node1 });
//! registry.add(node2, pathfinding.Position{ .x = 10, .y = 0 });
//!
//! // Find closest node to a position
//! const closest = try pathfinding.MovementNodeController.getClosestMovementNode(
//!     &registry,
//!     .{ .x = 5, .y = 0 },
//! );
//! ```
//!
//! ## Example (Floyd-Warshall)
//! ```zig
//! const pathfinding = @import("pathfinding");
//!
//! var fw = pathfinding.FloydWarshall.init(allocator);
//! defer fw.deinit();
//!
//! fw.resize(10);
//! try fw.clean();
//!
//! // Add edges between entities (using entity IDs as u32)
//! fw.addEdgeWithMapping(100, 200, 1);
//! fw.addEdgeWithMapping(200, 300, 1);
//!
//! // Generate shortest paths
//! fw.generate();
//!
//! // Query distance
//! const dist = fw.valueWithMapping(100, 300); // Returns 2
//! ```
//!
//! ## Example (A*)
//! ```zig
//! const pathfinding = @import("pathfinding");
//!
//! var astar = pathfinding.AStar.init(allocator);
//! defer astar.deinit();
//!
//! astar.resize(10);
//! try astar.clean();
//! astar.setHeuristic(.manhattan);
//!
//! // Set node positions for heuristic calculation
//! try astar.setNodePositionWithMapping(100, .{ .x = 0, .y = 0 });
//! try astar.setNodePositionWithMapping(200, .{ .x = 10, .y = 0 });
//!
//! // Add edges
//! astar.addEdgeWithMapping(100, 200, 1);
//!
//! // Find path (computed on-demand)
//! var path = std.array_list.Managed(u32).init(allocator);
//! const cost = try astar.findPathWithMapping(100, 200, &path);
//! ```

const std = @import("std");
pub const zig_utils = @import("zig_utils");
pub const ecs = @import("zig_ecs");

// Re-export Position (Vector2) from zig-utils for convenience
pub const Position = zig_utils.Vector2;

// Algorithms
pub const FloydWarshall = @import("floyd_warshall.zig").FloydWarshall;
pub const AStar = @import("a_star.zig").AStar;

// Heuristics
pub const heuristics = @import("heuristics.zig");
pub const Heuristic = heuristics.Heuristic;
pub const HeuristicFn = heuristics.HeuristicFn;

// Interfaces
pub const DistanceGraph = @import("distance_graph.zig").DistanceGraph;
pub const validateDistanceGraph = @import("distance_graph.zig").validateDistanceGraph;

// Components
pub const components = @import("components.zig");
pub const MovementNode = components.MovementNode;
pub const ClosestMovementNode = components.ClosestMovementNode;
pub const MovingTowards = components.MovingTowards;
pub const WithPath = components.WithPath;

// Controllers
pub const movement_node_controller = @import("movement_node_controller.zig");
pub const MovementNodeController = movement_node_controller.MovementNodeController;
pub const MovementNodeControllerError = movement_node_controller.MovementNodeControllerError;
pub const distance = movement_node_controller.distance;
pub const distanceSqr = movement_node_controller.distanceSqr;

// ECS types (re-exported from zig-ecs)
pub const Entity = ecs.Entity;
pub const Registry = ecs.Registry;

test {
    // Run all tests from submodules
    std.testing.refAllDecls(@This());
    _ = @import("floyd_warshall.zig");
    _ = @import("a_star.zig");
    _ = @import("heuristics.zig");
    _ = @import("components.zig");
    _ = @import("movement_node_controller.zig");
}
