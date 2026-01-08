//! Floyd-Warshall Algorithm Implementation
//!
//! Computes shortest paths between all pairs of vertices in a weighted graph.
//! Uses dynamic programming to find optimal paths and supports entity ID mapping
//! for use with ECS systems.
//!
//! This module wraps zig-utils FloydWarshall implementation and adds hook support.

const std = @import("std");
const zig_utils = @import("zig_utils");

const INF = std.math.maxInt(u32);

/// Floyd-Warshall all-pairs shortest path algorithm.
/// Wraps zig-utils implementation for compatibility.
/// Supports both direct vertex indices and entity ID mapping.
pub const FloydWarshall = struct {
    /// The underlying zig-utils Floyd-Warshall implementation
    base: zig_utils.FloydWarshall(u64),

    pub fn init(allocator: std.mem.Allocator) FloydWarshall {
        return .{
            .base = zig_utils.FloydWarshall(u64).init(allocator),
        };
    }

    pub fn deinit(self: *FloydWarshall) void {
        self.base.deinit();
    }

    /// Generate a new internal key for entity mapping
    pub fn newKey(self: *FloydWarshall) u32 {
        return self.base.newKey();
    }

    /// Add an edge between two vertices with given weight (direct index)
    pub fn addEdge(self: *FloydWarshall, u: u32, v: u32, w: u64) void {
        self.base.addEdge(u, v, w);
    }

    /// Get the distance between two vertices (direct index)
    pub fn value(self: *FloydWarshall, u: usize, v: usize) u64 {
        return self.base.value(u, v);
    }

    /// Check if a path exists between two vertices (direct index)
    pub fn hasPath(self: *FloydWarshall, u: usize, v: usize) bool {
        return self.base.hasPath(u, v);
    }

    /// Get the next vertex in the shortest path from u to v (direct index)
    pub fn next(self: *FloydWarshall, u: usize, v: usize) u32 {
        return self.base.next(u, v);
    }

    /// Resize the graph to support a given number of vertices
    pub fn resize(self: *FloydWarshall, size: u32) void {
        self.base.resize(size);
    }

    /// Add an edge using entity ID mapping (auto-assigns internal indices)
    pub fn addEdgeWithMapping(self: *FloydWarshall, u: u32, v: u32, w: u64) void {
        self.base.addEdgeWithMapping(u, v, w) catch |err| {
            std.log.err("Error inserting edge with mapping: {}\n", .{err});
        };
    }

    /// Get the distance between two entities (using ID mapping)
    pub fn valueWithMapping(self: *FloydWarshall, u: u32, v: u32) u64 {
        return self.base.valueWithMapping(u, v);
    }

    /// Build the path from u to v and store in the provided ArrayList
    pub fn setPathWithMapping(self: *FloydWarshall, path_list: *std.array_list.Managed(u32), u_node: u32, v_node: u32) !void {
        self.base.setPathWithMapping(path_list, u_node, v_node) catch |err| {
            if (err == error.PathNotFound) {
                std.log.err("No path found from {} to {}\n", .{ u_node, v_node });
            }
            return err;
        };
    }

    /// Build the path from u to v and store in the provided unmanaged ArrayList
    pub fn setPathWithMappingUnmanaged(self: *FloydWarshall, allocator: std.mem.Allocator, path_list: *std.ArrayListUnmanaged(u32), u_node: u32, v_node: u32) !void {
        self.base.setPathWithMappingUnmanaged(allocator, path_list, u_node, v_node) catch |err| {
            if (err == error.PathNotFound) {
                std.log.err("No path found from {} to {}\n", .{ u_node, v_node });
            }
            return err;
        };
    }

    /// Get the next entity in the shortest path from u to v (using ID mapping)
    pub fn nextWithMapping(self: *FloydWarshall, u: u32, v: u32) u32 {
        return self.base.nextWithMapping(u, v);
    }

    /// Check if a path exists between two entities (using ID mapping)
    pub fn hasPathWithMapping(self: *FloydWarshall, u: u32, v: u32) bool {
        return self.base.hasPathWithMapping(u, v);
    }

    /// Reset the graph and prepare for new data
    pub fn clean(self: *FloydWarshall) !void {
        try self.base.clean();
    }

    /// Run the Floyd-Warshall algorithm to compute all shortest paths
    pub fn generate(self: *FloydWarshall) void {
        self.base.generate();
    }
};

// ============================================================================
// Floyd-Warshall with Hooks
// ============================================================================

const hooks = @import("hooks.zig");

/// Floyd-Warshall algorithm with hook dispatching.
/// Wraps the base FloydWarshall and emits hooks at lifecycle points.
///
/// Example:
/// ```zig
/// const MyHooks = struct {
///     pub fn search_complete(payload: hooks.HookPayload) void {
///         std.log.info("All paths computed!", .{});
///     }
/// };
/// const Dispatcher = hooks.HookDispatcher(MyHooks);
/// var fw = FloydWarshallWithHooks(Dispatcher).init(allocator);
/// ```
pub fn FloydWarshallWithHooks(comptime Dispatcher: type) type {
    return struct {
        const Self = @This();

        /// The underlying Floyd-Warshall algorithm
        base: FloydWarshall,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .base = FloydWarshall.init(allocator) };
        }

        pub fn deinit(self: *Self) void {
            self.base.deinit();
        }

        // ====================================================================
        // Delegated methods (no hooks needed)
        // ====================================================================

        pub fn newKey(self: *Self) u32 {
            return self.base.newKey();
        }

        pub fn addEdge(self: *Self, u: u32, v: u32, w: u64) void {
            self.base.addEdge(u, v, w);
        }

        pub fn value(self: *Self, u: usize, v: usize) u64 {
            return self.base.value(u, v);
        }

        pub fn hasPath(self: *Self, u: usize, v: usize) bool {
            return self.base.hasPath(u, v);
        }

        pub fn next(self: *Self, u: usize, v: usize) u32 {
            return self.base.next(u, v);
        }

        pub fn resize(self: *Self, size: u32) void {
            self.base.resize(size);
        }

        pub fn addEdgeWithMapping(self: *Self, u: u32, v: u32, w: u64) void {
            self.base.addEdgeWithMapping(u, v, w);
        }

        pub fn valueWithMapping(self: *Self, u: u32, v: u32) u64 {
            return self.base.valueWithMapping(u, v);
        }

        pub fn nextWithMapping(self: *Self, u: u32, v: u32) u32 {
            return self.base.nextWithMapping(u, v);
        }

        pub fn hasPathWithMapping(self: *Self, u: u32, v: u32) bool {
            return self.base.hasPathWithMapping(u, v);
        }

        pub fn clean(self: *Self) !void {
            try self.base.clean();
        }

        // ====================================================================
        // Methods with hook dispatching
        // ====================================================================

        /// Run the Floyd-Warshall algorithm with hook dispatching.
        /// Emits search_complete hook when done.
        /// Note: Floyd-Warshall computes all-pairs shortest paths, so source/dest
        /// in the hook are set to 0 and nodes_explored reflects the O(n³) iterations.
        pub fn generate(self: *Self) void {
            const size = self.base.base.size;

            self.base.generate();

            // Emit search_complete hook
            // Note: source=0, dest=0 are placeholders since Floyd-Warshall computes all pairs
            Dispatcher.emit(.{ .search_complete = .{
                .source = 0,
                .dest = 0,
                .success = true,
                .nodes_explored = size * size * size,
                .path_length = 0,
                .cost = null,
            } });
        }

        /// Build the path from u to v and store in the provided ArrayList with hook dispatching
        pub fn setPathWithMapping(self: *Self, path_list: *std.array_list.Managed(u32), u: u32, v: u32) !void {
            // Emit path_requested hook
            Dispatcher.emit(.{ .path_requested = .{
                .source = u,
                .dest = v,
            } });

            self.base.setPathWithMapping(path_list, u, v) catch |err| {
                if (err == error.PathNotFound) {
                    // No path exists - nodes_explored is 0 since Floyd-Warshall
                    // precomputes all paths, no exploration happens during lookup
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

            // Calculate total cost
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
