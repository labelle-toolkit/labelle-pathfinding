//! Labelle Pathfinding
//!
//! A pathfinding library for Zig game development.
//! Part of the labelle-toolkit, uses zig-utils Vector2 for coordinates.
//! Provides node-based movement systems and shortest path algorithms.
//!
//! ## Features
//! - Floyd-Warshall all-pairs shortest path algorithm
//! - A* single-source shortest path algorithm with multiple heuristics
//! - Movement node components for ECS
//! - Spatial query controller for finding closest nodes
//! - Entity ID mapping for ECS integration
//!
//! ## Algorithm Selection Guide
//! - **A***: Best for single-source queries, large sparse graphs, real-time games
//! - **Floyd-Warshall**: Best when you need all-pairs paths, dense graphs, or
//!   when paths are queried repeatedly between many node pairs
//!
//! ## Example (Floyd-Warshall)
//! ```zig
//! const pathfinding = @import("pathfinding");
//!
//! // Create a distance graph
//! var fw = try pathfinding.FloydWarshall.init(allocator);
//! defer fw.deinit();
//!
//! fw.resize(10);
//! try fw.clean();
//!
//! // Add edges between entities
//! fw.addEdgeWithMapping(entity1, entity2, 1);
//! fw.addEdgeWithMapping(entity2, entity3, 1);
//!
//! // Generate shortest paths
//! fw.generate();
//!
//! // Find path
//! var path = std.array_list.Managed(u32).init(allocator);
//! try fw.setPathWithMapping(&path, entity1, entity3);
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
//!
//! // Set heuristic (default is euclidean)
//! astar.setHeuristic(.manhattan);
//!
//! // Set node positions for heuristic calculation
//! try astar.setNodePositionWithMapping(entity1, .{ .x = 0, .y = 0 });
//! try astar.setNodePositionWithMapping(entity2, .{ .x = 10, .y = 0 });
//!
//! // Add edges
//! astar.addEdgeWithMapping(entity1, entity2, 1);
//!
//! // Find path (computed on-demand)
//! var path = std.array_list.Managed(u32).init(allocator);
//! const cost = try astar.findPathWithMapping(entity1, entity2, &path);
//! ```

const std = @import("std");
pub const zig_utils = @import("zig_utils");

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
pub const EntityPosition = movement_node_controller.EntityPosition;
pub const Rectangle = movement_node_controller.Rectangle;
pub const distance = movement_node_controller.distance;
pub const distanceSqr = movement_node_controller.distanceSqr;

test {
    // Run all tests from submodules
    std.testing.refAllDecls(@This());
    _ = @import("floyd_warshall.zig");
    _ = @import("a_star.zig");
    _ = @import("heuristics.zig");
    _ = @import("components.zig");
    _ = @import("movement_node_controller.zig");
}
