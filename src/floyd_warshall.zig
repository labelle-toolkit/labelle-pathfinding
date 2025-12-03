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
    pub fn setPathWithMapping(self: *FloydWarshall, path_list: *std.array_list.Managed(u32), u_node: u32, v_node: u32) !void {
        var current = u_node;
        while (current != v_node) {
            try path_list.append(current);
            current = self.nextWithMapping(current, v_node);
            if (current == INF) {
                std.log.err("No path found from {} to {}\n", .{ u_node, v_node });
                return;
            }
        }
        try path_list.append(v_node);
    }

    /// Build the path from u to v and store in the provided unmanaged ArrayList
    pub fn setPathWithMappingUnmanaged(self: *FloydWarshall, allocator: std.mem.Allocator, path_list: *std.ArrayListUnmanaged(u32), u_node: u32, v_node: u32) !void {
        var current = u_node;
        while (current != v_node) {
            try path_list.append(allocator, current);
            current = self.nextWithMapping(current, v_node);
            if (current == INF) {
                std.log.err("No path found from {} to {}\n", .{ u_node, v_node });
                return;
            }
        }
        try path_list.append(allocator, v_node);
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
