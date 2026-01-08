//! A* (A-Star) Pathfinding Algorithm
//!
//! A best-first search algorithm that finds the shortest path between a source
//! and destination node. Uses heuristics to guide the search, making it more
//! efficient than Dijkstra's algorithm for single-source pathfinding.
//!
//! This module wraps zig-utils A* implementation and adds hook support.
//!
//! ## Features
//! - Single-source shortest path (efficient for point-to-point queries)
//! - Multiple built-in heuristics (Euclidean, Manhattan, Chebyshev, Octile)
//! - Custom heuristic support
//! - Entity ID mapping for integration with ECS systems
//! - Hook system for observability and debugging

const std = @import("std");
const zig_utils = @import("zig_utils");
const hooks = @import("hooks.zig");

pub const Heuristic = zig_utils.heuristics.Heuristic;
pub const HeuristicFn = zig_utils.heuristics.HeuristicFn;
pub const Position = zig_utils.heuristics.Position;

const INF = std.math.maxInt(u64);

/// A* pathfinding algorithm with configurable heuristics.
/// Wraps zig-utils implementation for compatibility.
/// Supports both direct vertex indices and entity ID mapping.
pub const AStar = struct {
    /// The underlying zig-utils A* implementation
    base: zig_utils.AStar(u64),

    pub fn init(allocator: std.mem.Allocator) AStar {
        return .{
            .base = zig_utils.AStar(u64).init(allocator) catch @panic("Failed to initialize AStar"),
        };
    }

    pub fn deinit(self: *AStar) void {
        self.base.deinit();
    }

    /// Set the heuristic type to use for pathfinding
    pub fn setHeuristic(self: *AStar, heuristic_type: Heuristic) void {
        self.base.setHeuristic(heuristic_type);
    }

    /// Set a custom heuristic function
    pub fn setCustomHeuristic(self: *AStar, heuristic_fn: HeuristicFn) void {
        self.base.setCustomHeuristic(heuristic_fn);
    }

    /// Set the position of a node (used for heuristic calculation)
    pub fn setNodePosition(self: *AStar, node: u32, pos: Position) !void {
        try self.base.setNodePosition(node, pos);
    }

    /// Set node position using entity ID mapping
    pub fn setNodePositionWithMapping(self: *AStar, entity: u32, pos: Position) !void {
        try self.base.setNodePositionWithMapping(entity, pos);
    }

    /// Resize the graph to support a given number of vertices
    pub fn resize(self: *AStar, size: u32) void {
        self.base.resize(size);
    }

    /// Reset the graph and prepare for new data
    pub fn clean(self: *AStar) !void {
        try self.base.clean();
    }

    /// Add an edge between two vertices with given weight (direct index)
    pub fn addEdge(self: *AStar, u: u32, v: u32, w: u64) !void {
        try self.base.addEdge(u, v, w);
    }

    /// Add an edge using entity ID mapping (auto-assigns internal indices)
    pub fn addEdgeWithMapping(self: *AStar, u: u32, v: u32, w: u64) !void {
        try self.base.addEdgeWithMapping(u, v, w);
    }

    /// Find path from source to destination (direct index)
    pub fn findPath(
        self: *AStar,
        source: u32,
        dest: u32,
        path: *std.array_list.Managed(u32),
    ) !?u64 {
        return try self.base.findPath(source, dest, path);
    }

    /// Find path using entity ID mapping
    pub fn findPathWithMapping(
        self: *AStar,
        source_entity: u32,
        dest_entity: u32,
        path: *std.array_list.Managed(u32),
    ) !?u64 {
        return try self.base.findPathWithMapping(source_entity, dest_entity, path);
    }

    /// Check if a path exists between two vertices (direct index)
    pub fn hasPath(self: *AStar, u: usize, v: usize) bool {
        return self.base.hasPath(u, v);
    }

    /// Check if a path exists between two entities (using ID mapping)
    pub fn hasPathWithMapping(self: *AStar, u: u32, v: u32) bool {
        return self.base.hasPathWithMapping(u, v);
    }

    /// Get the distance between two vertices (direct index)
    pub fn value(self: *AStar, u: usize, v: usize) u64 {
        return self.base.value(u, v);
    }

    /// Get the distance between two entities (using ID mapping)
    pub fn valueWithMapping(self: *AStar, u: u32, v: u32) u64 {
        return self.base.valueWithMapping(u, v);
    }

    /// Build the path from u to v and store in the provided ArrayList
    pub fn setPathWithMapping(self: *AStar, path_list: *std.array_list.Managed(u32), u: u32, v: u32) !void {
        try self.base.setPathWithMapping(path_list, u, v);
    }

    /// Get the next entity in the shortest path from u to v (using ID mapping)
    pub fn nextWithMapping(self: *AStar, u: u32, v: u32) u32 {
        return self.base.nextWithMapping(u, v);
    }

    /// Get the next vertex in the shortest path from u to v (direct index)
    pub fn next(self: *AStar, u: usize, v: usize) u32 {
        return self.base.next(u, v);
    }

    /// No-op for A* (paths computed on-demand)
    pub fn generate(self: *AStar) void {
        self.base.generate();
    }
};

// ============================================================================
// A* with Hooks
// ============================================================================

/// A* algorithm with hook dispatching.
/// Wraps the base AStar and emits hooks at pathfinding events.
///
/// Example:
/// ```zig
/// const MyHooks = struct {
///     pub fn path_found(payload: hooks.HookPayload) void {
///         const info = payload.path_found;
///         std.log.info("Found path with cost {}", .{info.cost});
///     }
/// };
/// const Dispatcher = hooks.HookDispatcher(MyHooks);
/// var astar = AStarWithHooks(Dispatcher).init(allocator);
/// ```
pub fn AStarWithHooks(comptime Dispatcher: type) type {
    return struct {
        const Self = @This();

        /// The underlying A* algorithm
        base: AStar,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .base = AStar.init(allocator) };
        }

        pub fn deinit(self: *Self) void {
            self.base.deinit();
        }

        // ====================================================================
        // Delegated methods (no hooks needed)
        // ====================================================================

        pub fn setHeuristic(self: *Self, heuristic_type: Heuristic) void {
            self.base.setHeuristic(heuristic_type);
        }

        pub fn setCustomHeuristic(self: *Self, heuristic_fn: HeuristicFn) void {
            self.base.setCustomHeuristic(heuristic_fn);
        }

        pub fn setNodePosition(self: *Self, node: u32, pos: Position) !void {
            try self.base.setNodePosition(node, pos);
        }

        pub fn setNodePositionWithMapping(self: *Self, entity: u32, pos: Position) !void {
            try self.base.setNodePositionWithMapping(entity, pos);
        }

        pub fn resize(self: *Self, size: u32) void {
            self.base.resize(size);
        }

        pub fn clean(self: *Self) !void {
            try self.base.clean();
        }

        pub fn addEdge(self: *Self, u: u32, v: u32, w: u64) !void {
            try self.base.addEdge(u, v, w);
        }

        pub fn addEdgeWithMapping(self: *Self, u: u32, v: u32, w: u64) !void {
            try self.base.addEdgeWithMapping(u, v, w);
        }

        pub fn hasPath(self: *Self, u: usize, v: usize) bool {
            return self.base.hasPath(u, v);
        }

        pub fn hasPathWithMapping(self: *Self, u: u32, v: u32) bool {
            return self.base.hasPathWithMapping(u, v);
        }

        pub fn value(self: *Self, u: usize, v: usize) u64 {
            return self.base.value(u, v);
        }

        pub fn valueWithMapping(self: *Self, u: u32, v: u32) u64 {
            return self.base.valueWithMapping(u, v);
        }

        pub fn nextWithMapping(self: *Self, u: u32, v: u32) u32 {
            return self.base.nextWithMapping(u, v);
        }

        pub fn next(self: *Self, u: usize, v: usize) u32 {
            return self.base.next(u, v);
        }

        pub fn generate(self: *Self) void {
            self.base.generate();
        }

        // ====================================================================
        // Methods with hook dispatching
        // ====================================================================

        /// Find path with hook dispatching
        pub fn findPath(
            self: *Self,
            source: u32,
            dest: u32,
            path: *std.array_list.Managed(u32),
        ) !?u64 {
            // Emit path_requested hook
            Dispatcher.emit(.{ .path_requested = .{
                .source = source,
                .dest = dest,
            } });

            const result = try self.base.findPath(source, dest, path);

            if (result) |cost| {
                Dispatcher.emit(.{ .path_found = .{
                    .source = source,
                    .dest = dest,
                    .cost = cost,
                    .path_length = path.items.len,
                } });
                Dispatcher.emit(.{ .search_complete = .{
                    .source = source,
                    .dest = dest,
                    .success = true,
                    .nodes_explored = 0, // A* doesn't track this in zig-utils
                    .path_length = path.items.len,
                    .cost = cost,
                } });
            } else {
                Dispatcher.emit(.{ .no_path_found = .{
                    .source = source,
                    .dest = dest,
                    .nodes_explored = 0,
                } });
                Dispatcher.emit(.{ .search_complete = .{
                    .source = source,
                    .dest = dest,
                    .success = false,
                    .nodes_explored = 0,
                    .path_length = 0,
                    .cost = null,
                } });
            }

            return result;
        }

        /// Find path using entity ID mapping with hook dispatching
        pub fn findPathWithMapping(
            self: *Self,
            source_entity: u32,
            dest_entity: u32,
            path: *std.array_list.Managed(u32),
        ) !?u64 {
            // Emit path_requested hook
            Dispatcher.emit(.{ .path_requested = .{
                .source = source_entity,
                .dest = dest_entity,
            } });

            const result = try self.base.findPathWithMapping(source_entity, dest_entity, path);

            if (result) |cost| {
                Dispatcher.emit(.{ .path_found = .{
                    .source = source_entity,
                    .dest = dest_entity,
                    .cost = cost,
                    .path_length = path.items.len,
                } });
                Dispatcher.emit(.{ .search_complete = .{
                    .source = source_entity,
                    .dest = dest_entity,
                    .success = true,
                    .nodes_explored = 0,
                    .path_length = path.items.len,
                    .cost = cost,
                } });
            } else {
                Dispatcher.emit(.{ .no_path_found = .{
                    .source = source_entity,
                    .dest = dest_entity,
                    .nodes_explored = 0,
                } });
                Dispatcher.emit(.{ .search_complete = .{
                    .source = source_entity,
                    .dest = dest_entity,
                    .success = false,
                    .nodes_explored = 0,
                    .path_length = 0,
                    .cost = null,
                } });
            }

            return result;
        }

        /// Build the path with hook dispatching
        pub fn setPathWithMapping(self: *Self, path_list: *std.array_list.Managed(u32), u: u32, v: u32) !void {
            // Emit path_requested hook
            Dispatcher.emit(.{ .path_requested = .{
                .source = u,
                .dest = v,
            } });

            self.base.setPathWithMapping(path_list, u, v) catch |err| {
                if (err == error.PathNotFound) {
                    Dispatcher.emit(.{ .no_path_found = .{
                        .source = u,
                        .dest = v,
                        .nodes_explored = 0,
                    } });
                    Dispatcher.emit(.{ .search_complete = .{
                        .source = u,
                        .dest = v,
                        .success = false,
                        .nodes_explored = 0,
                        .path_length = 0,
                        .cost = null,
                    } });
                }
                return err;
            };

            // Calculate cost from the path
            const cost = self.base.valueWithMapping(u, v);
            const path_length = path_list.items.len;

            Dispatcher.emit(.{ .path_found = .{
                .source = u,
                .dest = v,
                .cost = cost,
                .path_length = path_length,
            } });
            Dispatcher.emit(.{ .search_complete = .{
                .source = u,
                .dest = v,
                .success = true,
                .nodes_explored = 0,
                .path_length = path_length,
                .cost = cost,
            } });
        }
    };
}
