//! Labelle Pathfinding
//!
//! A pathfinding library for Zig game development.
//! Part of the labelle-toolkit, provides self-contained pathfinding systems
//! and shortest path algorithms.
//!
//! ## Features
//! - **PathfindingEngine**: Self-contained engine that owns entity positions
//! - Floyd-Warshall all-pairs shortest path algorithm
//! - A* single-source shortest path algorithm with multiple heuristics
//! - QuadTree spatial indexing for fast queries
//!
//! ## Algorithm Selection Guide
//! - **PathfindingEngine**: Best for most games - complete solution with position
//!   management, spatial queries, and movement
//! - **A***: Best for single-source queries, large sparse graphs, real-time games
//! - **Floyd-Warshall**: Best when you need all-pairs paths, dense graphs, or
//!   when paths are queried repeatedly between many node pairs
//!
//! ## Example (PathfindingEngine - Recommended)
//! ```zig
//! const pathfinding = @import("labelle_pathfinding");
//!
//! const Config = struct {
//!     pub const Entity = u64;
//!     pub const Context = *Game;
//! };
//!
//! var pf = pathfinding.PathfindingEngine(Config).init(allocator);
//! defer pf.deinit();
//!
//! // Build graph
//! try pf.addNode(0, 0, 0);
//! try pf.addNode(1, 100, 0);
//! try pf.addNode(2, 200, 0);
//! try pf.connectNodes(.{ .omnidirectional = .{ .max_distance = 150, .max_connections = 4 } });
//! try pf.rebuildPaths();
//!
//! // Register entity (pathfinding owns position)
//! try pf.registerEntity(player_id, 0, 0, 100);
//!
//! // Game loop
//! pf.tick(&game, delta);
//!
//! // Query position for rendering
//! if (pf.getPosition(player_id)) |pos| {
//!     renderer.draw(pos.x, pos.y);
//! }
//!
//! // Spatial query for combat
//! var nearby: [64]u64 = undefined;
//! const enemies = pf.getEntitiesInRadius(x, y, range, &nearby);
//! ```
//!
//! ## Example (Floyd-Warshall)
//! ```zig
//! const pathfinding = @import("labelle_pathfinding");
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
//! const pathfinding = @import("labelle_pathfinding");
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

// Shared types (extracted from engine.zig)
pub const types = @import("types.zig");
pub const Position = types.Position;
pub const Vec2 = types.Vec2;
pub const ConnectionMode = types.ConnectionMode;
pub const NodeId = types.NodeId;
pub const NodeData = types.NodeData;
pub const NodePoint = types.NodePoint;
pub const StairMode = types.StairMode;
pub const VerticalDirection = types.VerticalDirection;
pub const LogLevel = types.LogLevel;
pub const FloydWarshallVariant = types.FloydWarshallVariant;
pub const Grid = types.Grid;
pub const GridConfig = types.GridConfig;
pub const GridConnection = types.GridConnection;

// Engine (self-contained pathfinding)
pub const engine = @import("engine.zig");
pub const PathfindingEngine = engine.PathfindingEngine;
pub const PathfindingEngineSimple = engine.PathfindingEngineSimple;
pub const SimpleConfig = engine.SimpleConfig;

/// Components exported for ECS integration.
/// When labelle-pathfinding is added as a plugin, these types become available
/// in the component registry for use in .zon entity definitions.
pub const Components = struct {
    pub const Position = types.Position;
    pub const NodeId = types.NodeId;
    pub const NodePoint = types.NodePoint;
    /// A marker component for entities that are movement nodes in the pathfinding graph.
    pub const MovementNode = struct {
        node_id: u32 = 0,
    };
    /// Tracks the closest movement node to an entity, updated by pathfinding queries.
    pub const ClosestMovementNode = struct {
        node_entity: u64 = 0,
        node_id: u32 = 0,
        distance: f32 = 0.0,
    };
};

// Spatial indexing
pub const quad_tree = @import("quad_tree.zig");
pub const QuadTree = quad_tree.QuadTree;
pub const Rectangle = quad_tree.Rectangle;

// Algorithms
pub const FloydWarshall = @import("floyd_warshall.zig").FloydWarshall;
pub const FloydWarshallWithHooks = @import("floyd_warshall.zig").FloydWarshallWithHooks;
pub const AStar = @import("a_star.zig").AStar;
pub const AStarWithHooks = @import("a_star.zig").AStarWithHooks;

// Hook system
pub const hooks = @import("hooks.zig");

// Optimized Floyd-Warshall variants
pub const floyd_warshall_optimized = @import("floyd_warshall_optimized.zig");
pub const FloydWarshallOptimized = floyd_warshall_optimized.FloydWarshallOptimized;
pub const FloydWarshallParallel = floyd_warshall_optimized.FloydWarshallParallel;
pub const FloydWarshallSimd = floyd_warshall_optimized.FloydWarshallSimd;
pub const FloydWarshallScalar = floyd_warshall_optimized.FloydWarshallScalar;

// Heuristics
pub const heuristics = @import("heuristics.zig");
pub const Heuristic = heuristics.Heuristic;
pub const HeuristicFn = heuristics.HeuristicFn;

// Interfaces
pub const DistanceGraph = @import("distance_graph.zig").DistanceGraph;
pub const validateDistanceGraph = @import("distance_graph.zig").validateDistanceGraph;

test {
    // Run all tests from submodules
    std.testing.refAllDecls(@This());
    _ = @import("types.zig");
    _ = @import("engine.zig");
    _ = @import("quad_tree.zig");
    _ = @import("floyd_warshall.zig");
    _ = @import("floyd_warshall_optimized.zig");
    _ = @import("a_star.zig");
    _ = @import("heuristics.zig");
    _ = @import("hooks.zig");
}
