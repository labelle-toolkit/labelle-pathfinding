//! Floyd-Warshall Algorithm Implementation
//!
//! Computes shortest paths between all pairs of vertices in a weighted graph.
//! Uses dynamic programming to find optimal paths and supports entity ID mapping.
//!
//! Complexity: O(V³) time, O(V²) space
//!
//! Best for:
//! - Dense graphs with many all-pairs queries
//! - Graphs that change infrequently
//! - Pre-computing all shortest paths

const std = @import("std");

/// Floyd-Warshall all-pairs shortest path algorithm.
/// Generic over DistanceType for memory efficiency.
/// Supports both direct vertex indices and entity ID mapping.
pub fn FloydWarshall(comptime DistanceType: type) type {
    comptime {
        const info = @typeInfo(DistanceType);
        if (info != .int or info.int.signedness != .unsigned) {
            @compileError("DistanceType must be an unsigned integer type");
        }
    }

    const INF = std.math.maxInt(DistanceType);

    return struct {
        const Self = @This();
        const RowList = std.array_list.Managed(DistanceType);
        const GraphList = std.array_list.Managed(RowList);

        size: u32 = 100,
        graph: GraphList,
        path: GraphList,
        ids: std.AutoHashMap(u32, u32),
        /// Reverse mapping: internal index to entity ID for O(1) reverse lookups
        reverse_ids: std.AutoHashMap(u32, u32),
        last_key: u32 = 0,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .graph = GraphList.init(allocator),
                .path = GraphList.init(allocator),
                .ids = std.AutoHashMap(u32, u32).init(allocator),
                .reverse_ids = std.AutoHashMap(u32, u32).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.graph.items) |*row| {
                row.deinit();
            }
            for (self.path.items) |*row| {
                row.deinit();
            }
            self.graph.deinit();
            self.path.deinit();
            self.ids.deinit();
            self.reverse_ids.deinit();
        }

        /// Generate a new internal key for entity mapping
        pub fn newKey(self: *Self) u32 {
            self.last_key += 1;
            return self.last_key - 1;
        }

        /// Add an edge between two vertices with given weight (direct index)
        pub fn addEdge(self: *Self, u: u32, v: u32, w: DistanceType) void {
            self.graph.items[u].items[v] = w;
        }

        /// Get the distance between two vertices (direct index)
        pub fn value(self: *Self, u: usize, v: usize) DistanceType {
            return self.graph.items[u].items[v];
        }

        /// Check if a path exists between two vertices (direct index)
        pub fn hasPath(self: *Self, u: usize, v: usize) bool {
            return self.graph.items[u].items[v] != INF;
        }

        /// Get the next vertex in the shortest path from u to v (direct index)
        pub fn next(self: *Self, u: usize, v: usize) u32 {
            return @intCast(self.path.items[u].items[v]);
        }

        /// Resize the graph to support a given number of vertices
        pub fn resize(self: *Self, size: u32) void {
            self.size = size;
        }

        /// Add an edge using entity ID mapping (auto-assigns internal indices)
        /// Returns error.OutOfMemory if the internal hash map fails to allocate
        pub fn addEdgeWithMapping(self: *Self, u: u32, v: u32, w: DistanceType) !void {
            if (!self.ids.contains(u)) {
                const key = self.newKey();
                try self.ids.put(u, key);
                errdefer _ = self.ids.remove(u);
                try self.reverse_ids.put(key, u);
            }
            if (!self.ids.contains(v)) {
                const key = self.newKey();
                try self.ids.put(v, key);
                errdefer _ = self.ids.remove(v);
                try self.reverse_ids.put(key, v);
            }
            self.addEdge(self.ids.get(u).?, self.ids.get(v).?, w);
        }

        /// Get the distance between two entities (using ID mapping)
        pub fn valueWithMapping(self: *Self, u: u32, v: u32) DistanceType {
            return self.value(self.ids.get(u).?, self.ids.get(v).?);
        }

        /// Build the path from u to v and store in the provided ArrayList
        /// Returns error.PathNotFound if no path exists between the nodes.
        pub fn setPathWithMapping(self: *Self, path_list: *std.array_list.Managed(u32), u_node: u32, v_node: u32) !void {
            const initial_len = path_list.items.len;
            var current = u_node;
            while (current != v_node) {
                try path_list.append(current);
                current = self.nextWithMapping(current, v_node);
                if (current == std.math.maxInt(u32)) {
                    // Clear partial path data before returning error
                    path_list.shrinkRetainingCapacity(initial_len);
                    return error.PathNotFound;
                }
            }
            try path_list.append(v_node);
        }

        /// Build the path from u to v and store in the provided unmanaged ArrayList
        /// Returns error.PathNotFound if no path exists between the nodes.
        pub fn setPathWithMappingUnmanaged(self: *Self, allocator: std.mem.Allocator, path_list: *std.ArrayListUnmanaged(u32), u_node: u32, v_node: u32) !void {
            const initial_len = path_list.items.len;
            var current = u_node;
            while (current != v_node) {
                try path_list.append(allocator, current);
                current = self.nextWithMapping(current, v_node);
                if (current == std.math.maxInt(u32)) {
                    // Clear partial path data before returning error
                    path_list.shrinkRetainingCapacity(initial_len);
                    return error.PathNotFound;
                }
            }
            try path_list.append(allocator, v_node);
        }

        /// Get the next entity in the shortest path from u to v (using ID mapping)
        /// Uses O(1) reverse lookup via reverse_ids map.
        pub fn nextWithMapping(self: *Self, u: u32, v: u32) u32 {
            const u_idx = self.ids.get(u) orelse return std.math.maxInt(u32);
            const v_idx = self.ids.get(v) orelse return std.math.maxInt(u32);
            const next_idx = self.next(u_idx, v_idx);
            return self.reverse_ids.get(next_idx) orelse std.math.maxInt(u32);
        }

        /// Check if a path exists between two entities (using ID mapping)
        pub fn hasPathWithMapping(self: *Self, u: u32, v: u32) bool {
            if (self.ids.get(u) == null or self.ids.get(v) == null) {
                return false;
            }
            return self.hasPath(self.ids.get(u).?, self.ids.get(v).?);
        }

        /// Reset the graph and prepare for new data
        pub fn clean(self: *Self) !void {
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
            self.reverse_ids.clearRetainingCapacity();

            // Initialize adjacency matrix and path matrix
            for (0..self.size) |_| {
                var list = RowList.init(self.allocator);
                var list_appended = false;
                errdefer if (!list_appended) list.deinit();

                var row_path = RowList.init(self.allocator);
                var row_path_appended = false;
                errdefer if (!row_path_appended) row_path.deinit();

                for (0..self.size) |_| {
                    try list.append(0);
                    try row_path.append(0);
                }
                try self.graph.append(list);
                list_appended = true;

                try self.path.append(row_path);
                row_path_appended = true;
            }

            // Set initial values: 0 for self-loops, INF for no edge
            for (0..self.size) |i| {
                for (0..self.size) |j| {
                    self.path.items[i].items[j] = @intCast(j);
                    if (i == j) {
                        self.graph.items[i].items[j] = 0;
                    } else {
                        self.graph.items[i].items[j] = INF;
                    }
                }
            }
        }

        /// Run the Floyd-Warshall algorithm to compute all shortest paths
        pub fn generate(self: *Self) void {
            for (0..self.size) |k| {
                for (0..self.size) |i| {
                    const dist_ik = self.graph.items[i].items[k];
                    if (dist_ik == INF) continue; // Skip if no path to k

                    for (0..self.size) |j| {
                        const dist_kj = self.graph.items[k].items[j];
                        if (dist_kj == INF) continue; // Skip if no path from k

                        const new_dist = dist_ik +| dist_kj; // Saturating add
                        if (new_dist < self.graph.items[i].items[j]) {
                            self.graph.items[i].items[j] = new_dist;
                            self.path.items[i].items[j] = self.path.items[i].items[k];
                        }
                    }
                }
            }
        }
    };
}
