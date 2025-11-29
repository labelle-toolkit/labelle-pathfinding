//! Labelle Pathfinding
//!
//! A pathfinding library for Zig game development.
//! Provides node-based movement systems and shortest path algorithms.
//!
//! ## Features
//! - Floyd-Warshall all-pairs shortest path algorithm
//! - Movement node components for ECS
//! - Spatial query controller for finding closest nodes
//! - Entity ID mapping for ECS integration
//!
//! ## Example
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
//! var path = std.ArrayList(u32).init(allocator);
//! try fw.setPathWithMapping(&path, entity1, entity3);
//! ```

const std = @import("std");

// Algorithms
pub const FloydWarshall = @import("floyd_warshall.zig").FloydWarshall;

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
pub const Vector2 = movement_node_controller.Vector2;
pub const Rectangle = movement_node_controller.Rectangle;

test {
    // Run all tests from submodules
    std.testing.refAllDecls(@This());
    _ = @import("floyd_warshall.zig");
    _ = @import("components.zig");
    _ = @import("movement_node_controller.zig");
}
