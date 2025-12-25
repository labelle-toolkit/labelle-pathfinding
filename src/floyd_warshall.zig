//! Floyd-Warshall Algorithm Implementation
//!
//! Computes shortest paths between all pairs of vertices in a weighted graph.
//! Uses dynamic programming to find optimal paths and supports entity ID mapping
//! for use with ECS systems.

const std = @import("std");

const INF = std.math.maxInt(u32);

/// Floyd-Warshall all-pairs shortest path algorithm.
/// Supports both direct vertex indices and entity ID mapping.
pub const FloydWarshall = struct {
    const RowList = std.array_list.Managed(u64);
    const GraphList = std.array_list.Managed(RowList);

    size: u32 = 100,
    graph: GraphList,
    path: GraphList,
    ids: std.AutoHashMap(u32, u32),
    last_key: u32 = 0,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FloydWarshall {
        return .{
            .graph = GraphList.init(allocator),
            .path = GraphList.init(allocator),
            .ids = std.AutoHashMap(u32, u32).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FloydWarshall) void {
        for (self.graph.items) |*row| {
            row.deinit();
        }
        for (self.path.items) |*row| {
            row.deinit();
        }
        self.graph.deinit();
        self.path.deinit();
        self.ids.deinit();
    }

    /// Generate a new internal key for entity mapping
    pub fn newKey(self: *FloydWarshall) u32 {
        self.last_key += 1;
        return self.last_key - 1;
    }

    /// Add an edge between two vertices with given weight (direct index)
    pub fn addEdge(self: *FloydWarshall, u: u32, v: u32, w: u64) void {
        self.graph.items[u].items[v] = w;
    }

    /// Get the distance between two vertices (direct index)
    pub fn value(self: *FloydWarshall, u: usize, v: usize) u64 {
        return self.graph.items[u].items[v];
    }

    /// Check if a path exists between two vertices (direct index)
    pub fn hasPath(self: *FloydWarshall, u: usize, v: usize) bool {
        return self.graph.items[u].items[v] != INF;
    }

    /// Get the next vertex in the shortest path from u to v (direct index)
    pub fn next(self: *FloydWarshall, u: usize, v: usize) u32 {
        return @intCast(self.path.items[u].items[v]);
    }

    /// Resize the graph to support a given number of vertices
    pub fn resize(self: *FloydWarshall, size: u32) void {
        self.size = size;
    }

    /// Add an edge using entity ID mapping (auto-assigns internal indices)
    pub fn addEdgeWithMapping(self: *FloydWarshall, u: u32, v: u32, w: u64) void {
        if (!self.ids.contains(u)) {
            self.ids.put(u, self.newKey()) catch |err| {
                std.log.err("Error inserting on map: {}\n", .{err});
            };
        }
        if (!self.ids.contains(v)) {
            self.ids.put(v, self.newKey()) catch |err| {
                std.log.err("Error inserting on map: {}\n", .{err});
            };
        }
        self.addEdge(self.ids.get(u).?, self.ids.get(v).?, w);
    }

    /// Get the distance between two entities (using ID mapping)
    pub fn valueWithMapping(self: *FloydWarshall, u: u32, v: u32) u64 {
        return self.value(self.ids.get(u).?, self.ids.get(v).?);
    }

    /// Build the path from u to v and store in the provided ArrayList
    pub fn setPathWithMapping(self: *FloydWarshall, path_list: *std.array_list.Managed(u32), u: u32, v: u32) !void {
        var current = u;
        while (current != v) {
            try path_list.append(current);
            current = self.nextWithMapping(current, v);
            if (current == INF) {
                std.log.err("No path found from {} to {}\n", .{ u, v });
                return;
            }
        }
        try path_list.append(v);
    }

    /// Get the next entity in the shortest path from u to v (using ID mapping)
    pub fn nextWithMapping(self: *FloydWarshall, u: u32, v: u32) u32 {
        const val = self.next(self.ids.get(u).?, self.ids.get(v).?);
        var result = self.ids.iterator();
        while (result.next()) |entry| {
            if (entry.value_ptr.* == val) {
                return entry.key_ptr.*;
            }
        }
        return INF;
    }

    /// Check if a path exists between two entities (using ID mapping)
    pub fn hasPathWithMapping(self: *FloydWarshall, u: u32, v: u32) bool {
        if (self.ids.get(u) == null or self.ids.get(v) == null) {
            return false;
        }
        return self.hasPath(self.ids.get(u).?, self.ids.get(v).?);
    }

    /// Reset the graph and prepare for new data
    pub fn clean(self: *FloydWarshall) !void {
        self.last_key = 0;
        for (self.graph.items) |*row| {
            row.deinit();
        }
        for (self.path.items) |*row| {
            row.deinit();
        }
        self.graph.clearRetainingCapacity();
        self.path.clearRetainingCapacity();
        self.ids.clearRetainingCapacity();

        // Initialize adjacency matrix and path matrix
        for (0..self.size) |_| {
            var list = RowList.init(self.allocator);
            var row_path = RowList.init(self.allocator);
            for (0..self.size) |_| {
                try list.append(0);
                try row_path.append(0);
            }
            try self.graph.append(list);
            try self.path.append(row_path);
        }

        // Set initial values: 0 for self-loops, INF for no edge
        for (0..self.size) |i| {
            for (0..self.size) |j| {
                self.path.items[i].items[j] = j;
                if (i == j) {
                    self.graph.items[i].items[j] = 0;
                } else {
                    self.graph.items[i].items[j] = INF;
                }
            }
        }
    }

    /// Run the Floyd-Warshall algorithm to compute all shortest paths
    pub fn generate(self: *FloydWarshall) void {
        for (0..self.size) |k| {
            for (0..self.size) |i| {
                for (0..self.size) |j| {
                    if (self.graph.items[i].items[k] + self.graph.items[k].items[j] < self.graph.items[i].items[j]) {
                        self.graph.items[i].items[j] = self.graph.items[i].items[k] + self.graph.items[k].items[j];
                        self.path.items[i].items[j] = self.path.items[i].items[k];
                    }
                }
            }
        }
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
        pub fn generate(self: *Self) void {
            const size = self.base.size;
            var paths_found: u32 = 0;

            for (0..size) |k| {
                for (0..size) |i| {
                    for (0..size) |j| {
                        if (self.base.graph.items[i].items[k] + self.base.graph.items[k].items[j] < self.base.graph.items[i].items[j]) {
                            self.base.graph.items[i].items[j] = self.base.graph.items[i].items[k] + self.base.graph.items[k].items[j];
                            self.base.path.items[i].items[j] = self.base.path.items[i].items[k];
                            paths_found += 1;
                        }
                    }
                }
            }

            // Emit search_complete hook
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

            var current = u;
            var path_length: usize = 0;
            while (current != v) {
                try path_list.append(current);
                path_length += 1;
                current = self.base.nextWithMapping(current, v);
                if (current == INF) {
                    Dispatcher.emit(.{ .no_path_found = .{
                        .source = u,
                        .dest = v,
                        .nodes_explored = @intCast(path_length),
                    } });
                    return;
                }
            }
            try path_list.append(v);
            path_length += 1;

            // Calculate total cost
            const cost = self.base.valueWithMapping(u, v);

            Dispatcher.emit(.{ .path_found = .{
                .source = u,
                .dest = v,
                .cost = cost,
                .path_length = path_length,
            } });
        }
    };
}

// ============================================================================
// Tests for FloydWarshallWithHooks
// ============================================================================

test "FloydWarshallWithHooks emits search_complete hook" {
    const TestHooks = struct {
        var search_complete_called: bool = false;

        pub fn search_complete(_: hooks.HookPayload) void {
            search_complete_called = true;
        }
    };

    const Dispatcher = hooks.HookDispatcher(TestHooks);
    var fw = FloydWarshallWithHooks(Dispatcher).init(std.testing.allocator);
    defer fw.deinit();

    fw.resize(3);
    try fw.clean();

    fw.addEdge(0, 1, 10);
    fw.addEdge(1, 2, 5);

    TestHooks.search_complete_called = false;

    fw.generate();

    try std.testing.expect(TestHooks.search_complete_called);
}

test "FloydWarshallWithHooks emits path_found hook on setPathWithMapping" {
    const TestHooks = struct {
        var path_found_called: bool = false;
        var last_cost: u64 = 0;

        pub fn path_found(payload: hooks.HookPayload) void {
            const info = payload.path_found;
            path_found_called = true;
            last_cost = info.cost;
        }
    };

    const Dispatcher = hooks.HookDispatcher(TestHooks);
    var fw = FloydWarshallWithHooks(Dispatcher).init(std.testing.allocator);
    defer fw.deinit();

    fw.resize(3);
    try fw.clean();

    fw.addEdgeWithMapping(100, 200, 10);
    fw.addEdgeWithMapping(200, 300, 5);

    fw.generate();

    TestHooks.path_found_called = false;
    TestHooks.last_cost = 0;

    var path = std.array_list.Managed(u32).init(std.testing.allocator);
    defer path.deinit();

    try fw.setPathWithMapping(&path, 100, 300);

    try std.testing.expect(TestHooks.path_found_called);
    try std.testing.expectEqual(@as(u64, 15), TestHooks.last_cost);
}
