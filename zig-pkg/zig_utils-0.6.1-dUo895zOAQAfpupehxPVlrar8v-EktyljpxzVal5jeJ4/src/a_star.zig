//! A* (A-Star) Pathfinding Algorithm
//!
//! A best-first search algorithm that finds the shortest path between a source
//! and destination node. Uses heuristics to guide the search, making it more
//! efficient than Dijkstra's algorithm for single-source pathfinding.
//!
//! ## Features
//! - Single-source shortest path (efficient for point-to-point queries)
//! - Multiple built-in heuristics (Euclidean, Manhattan, Chebyshev, Octile)
//! - Custom heuristic support
//! - Entity ID mapping for integration with external systems
//! - Adjacency list representation (memory efficient for sparse graphs)
//!
//! ## When to use A* vs Floyd-Warshall
//! - **A***: Best for single-source queries, large sparse graphs, real-time games
//! - **Floyd-Warshall**: Best when you need all-pairs paths, dense graphs, or
//!   when paths are queried repeatedly between many node pairs

const std = @import("std");
const heuristics_mod = @import("heuristics.zig");
const SparseSet = @import("sparse_set.zig").SparseSet;

pub const Heuristic = heuristics_mod.Heuristic;
pub const HeuristicFn = heuristics_mod.HeuristicFn;
pub const Position = heuristics_mod.Position;

/// A* pathfinding algorithm with configurable heuristics.
/// Generic over WeightType for memory efficiency.
/// Supports both direct vertex indices and entity ID mapping.
pub fn AStar(comptime WeightType: type) type {
    comptime {
        const info = @typeInfo(WeightType);
        if (info != .int or info.int.signedness != .unsigned) {
            @compileError("WeightType must be an unsigned integer type");
        }
    }

    const INF = std.math.maxInt(WeightType);

    return struct {
        const Self = @This();

        const Edge = struct {
            to: u32,
            weight: WeightType,
        };
        const EdgeList = std.ArrayListUnmanaged(Edge);
        const AdjacencyList = std.ArrayListUnmanaged(EdgeList);

        /// Priority queue node for A* open set
        const PQNode = struct {
            vertex: u32,
            f_score: f32,

            fn compare(_: void, a: PQNode, b: PQNode) std.math.Order {
                return std.math.order(a.f_score, b.f_score);
            }
        };

        allocator: std.mem.Allocator,
        adjacency: AdjacencyList,
        positions: SparseSet(u32, Position),
        ids: SparseSet(u32, u32),
        reverse_ids: SparseSet(u32, u32),
        last_key: u32 = 0,
        size: u32 = 100,
        heuristic_type: Heuristic,
        custom_heuristic: ?HeuristicFn,

        pub fn init(allocator: std.mem.Allocator) !Self {
            var positions = try SparseSet(u32, Position).init(allocator, 1024, 64);
            errdefer positions.deinit();

            var ids = try SparseSet(u32, u32).init(allocator, 1024, 64);
            errdefer ids.deinit();

            const reverse_ids = try SparseSet(u32, u32).init(allocator, 1024, 64);

            return .{
                .allocator = allocator,
                .adjacency = .empty,
                .positions = positions,
                .ids = ids,
                .reverse_ids = reverse_ids,
                .heuristic_type = .euclidean,
                .custom_heuristic = null,
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.adjacency.items) |*edges| {
                edges.deinit(self.allocator);
            }
            self.adjacency.deinit(self.allocator);
            self.positions.deinit();
            self.ids.deinit();
            self.reverse_ids.deinit();
        }

        /// Set the heuristic type to use for pathfinding
        pub fn setHeuristic(self: *Self, heuristic_type: Heuristic) void {
            self.heuristic_type = heuristic_type;
            self.custom_heuristic = null;
        }

        /// Set a custom heuristic function
        pub fn setCustomHeuristic(self: *Self, heuristic_fn: HeuristicFn) void {
            self.custom_heuristic = heuristic_fn;
        }

        /// Set the position of a node (used for heuristic calculation)
        pub fn setNodePosition(self: *Self, node: u32, pos: Position) !void {
            try self.positions.put(node, pos);
        }

        /// Set node position using entity ID mapping
        pub fn setNodePositionWithMapping(self: *Self, entity: u32, pos: Position) !void {
            const internal_id = try self.getOrCreateMapping(entity);
            try self.positions.put(internal_id, pos);
        }

        /// Generate a new internal key for entity mapping
        fn newKey(self: *Self) u32 {
            self.last_key += 1;
            return self.last_key - 1;
        }

        /// Get or create an internal ID mapping for an entity
        fn getOrCreateMapping(self: *Self, entity: u32) !u32 {
            if (self.ids.get(entity)) |id| {
                return id;
            }
            const new_id = self.newKey();
            try self.ids.put(entity, new_id);
            errdefer _ = self.ids.remove(entity);
            try self.reverse_ids.put(new_id, entity);
            return new_id;
        }

        /// Resize the graph to support a given number of vertices
        pub fn resize(self: *Self, size: u32) void {
            self.size = size;
        }

        /// Reset the graph and prepare for new data
        pub fn clean(self: *Self) !void {
            self.last_key = 0;

            for (self.adjacency.items) |*edges| {
                edges.deinit(self.allocator);
            }
            self.adjacency.clearRetainingCapacity();
            self.positions.clear();
            self.ids.clear();
            self.reverse_ids.clear();

            // Initialize adjacency lists for each vertex
            try self.adjacency.ensureTotalCapacity(self.allocator, self.size);
            for (0..self.size) |_| {
                try self.adjacency.append(self.allocator, .empty);
            }
        }

        pub const AddEdgeError = error{
            InvalidVertex,
            OutOfMemory,
        };

        /// Add an edge between two vertices with given weight (direct index)
        /// Returns error.InvalidVertex if u or v is out of bounds.
        pub fn addEdge(self: *Self, u: u32, v: u32, w: WeightType) AddEdgeError!void {
            if (u >= self.adjacency.items.len or v >= self.adjacency.items.len) {
                return error.InvalidVertex;
            }
            try self.adjacency.items[u].append(self.allocator, .{ .to = v, .weight = w });
        }

        /// Add an edge using entity ID mapping (auto-assigns internal indices)
        pub fn addEdgeWithMapping(self: *Self, u: u32, v: u32, w: WeightType) !void {
            const u_internal = try self.getOrCreateMapping(u);
            const v_internal = try self.getOrCreateMapping(v);
            try self.addEdge(u_internal, v_internal, w);
        }

        /// Calculate heuristic between two internal vertex indices
        fn calculateHeuristic(self: *Self, from: u32, to: u32) f32 {
            const from_pos = self.positions.get(from) orelse Position{ .x = 0, .y = 0 };
            const to_pos = self.positions.get(to) orelse Position{ .x = 0, .y = 0 };

            if (self.custom_heuristic) |custom| {
                return custom(from_pos, to_pos);
            }
            return heuristics_mod.calculate(self.heuristic_type, from_pos, to_pos);
        }

        /// Run A* algorithm to find shortest path from source to destination.
        /// Returns the path cost, or null if no path exists.
        /// The path is stored in the provided ArrayList.
        pub fn findPath(
            self: *Self,
            source: u32,
            dest: u32,
            path: *std.array_list.Managed(u32),
        ) !?WeightType {
            const n = self.adjacency.items.len;
            if (source >= n or dest >= n) {
                return null;
            }

            path.clearRetainingCapacity();

            if (source == dest) {
                try path.append(source);
                return 0;
            }

            // Flat arrays instead of HashMaps - O(1) access, cache-friendly
            const g_score = try self.allocator.alloc(WeightType, n);
            defer self.allocator.free(g_score);
            @memset(g_score, INF);

            const came_from = try self.allocator.alloc(u32, n);
            defer self.allocator.free(came_from);
            @memset(came_from, std.math.maxInt(u32)); // maxInt = no parent

            // BitSet instead of HashMap for closed_set - ~32x smaller, faster
            var closed_set = try std.DynamicBitSet.initEmpty(self.allocator, n);
            defer closed_set.deinit();

            var open_set = std.PriorityQueue(PQNode, void, PQNode.compare).init(self.allocator, {});
            defer open_set.deinit();

            // Initialize source
            g_score[source] = 0;
            const h = self.calculateHeuristic(source, dest);
            try open_set.add(.{ .vertex = source, .f_score = h });

            while (open_set.removeOrNull()) |current| {
                if (current.vertex == dest) {
                    // Reconstruct path
                    var node = dest;
                    while (true) {
                        try path.append(node);
                        const parent = came_from[node];
                        if (parent == std.math.maxInt(u32)) {
                            break;
                        }
                        node = parent;
                    }
                    // Reverse to get source -> dest order
                    std.mem.reverse(u32, path.items);
                    return g_score[dest];
                }

                if (closed_set.isSet(current.vertex)) {
                    continue;
                }
                closed_set.set(current.vertex);

                const current_g = g_score[current.vertex];

                // Explore neighbors
                for (self.adjacency.items[current.vertex].items) |edge| {
                    if (closed_set.isSet(edge.to)) {
                        continue;
                    }

                    const tentative_g = current_g +| edge.weight; // Saturating add
                    const neighbor_g = g_score[edge.to];

                    if (tentative_g < neighbor_g) {
                        came_from[edge.to] = current.vertex;
                        g_score[edge.to] = tentative_g;

                        const f = @as(f32, @floatFromInt(tentative_g)) + self.calculateHeuristic(edge.to, dest);
                        try open_set.add(.{ .vertex = edge.to, .f_score = f });
                    }
                }
            }

            return null; // No path found
        }

        pub const MappingError = error{
            CorruptedMapping,
            OutOfMemory,
        };

        /// Find path using entity ID mapping
        /// Returns error.CorruptedMapping if internal nodes cannot be reverse-mapped.
        pub fn findPathWithMapping(
            self: *Self,
            source_entity: u32,
            dest_entity: u32,
            path: *std.array_list.Managed(u32),
        ) MappingError!?WeightType {
            const source = self.ids.get(source_entity) orelse return null;
            const dest = self.ids.get(dest_entity) orelse return null;

            var internal_path = std.array_list.Managed(u32).init(self.allocator);
            defer internal_path.deinit();

            const cost = self.findPath(source, dest, &internal_path) catch return error.OutOfMemory;

            if (cost != null) {
                path.clearRetainingCapacity();
                for (internal_path.items) |internal_id| {
                    const entity = self.reverse_ids.get(internal_id) orelse return error.CorruptedMapping;
                    try path.append(entity);
                }
            }

            return cost;
        }

        /// Check if a path exists between two vertices (direct index)
        pub fn hasPath(self: *Self, u: usize, v: usize) bool {
            var path = std.array_list.Managed(u32).init(self.allocator);
            defer path.deinit();

            const result = self.findPath(@intCast(u), @intCast(v), &path) catch return false;
            return result != null;
        }

        /// Check if a path exists between two entities (using ID mapping)
        pub fn hasPathWithMapping(self: *Self, u: u32, v: u32) bool {
            var path = std.array_list.Managed(u32).init(self.allocator);
            defer path.deinit();

            const result = self.findPathWithMapping(u, v, &path) catch return false;
            return result != null;
        }

        /// Get the distance between two vertices (direct index)
        /// Note: This runs A* each time - cache results if needed frequently
        pub fn value(self: *Self, u: usize, v: usize) WeightType {
            var path = std.array_list.Managed(u32).init(self.allocator);
            defer path.deinit();

            const result = self.findPath(@intCast(u), @intCast(v), &path) catch return INF;
            return result orelse INF;
        }

        /// Get the distance between two entities (using ID mapping)
        pub fn valueWithMapping(self: *Self, u: u32, v: u32) WeightType {
            var path = std.array_list.Managed(u32).init(self.allocator);
            defer path.deinit();

            const result = self.findPathWithMapping(u, v, &path) catch return INF;
            return result orelse INF;
        }

        pub const PathError = error{
            PathNotFound,
            CorruptedMapping,
            OutOfMemory,
        };

        /// Build the path from u to v and store in the provided ArrayList
        /// Returns error.PathNotFound if no path exists between the nodes.
        pub fn setPathWithMapping(self: *Self, path_list: *std.array_list.Managed(u32), u: u32, v: u32) PathError!void {
            var path = std.array_list.Managed(u32).init(self.allocator);
            defer path.deinit();

            const result = try self.findPathWithMapping(u, v, &path);
            if (result == null) {
                return error.PathNotFound;
            }

            path_list.clearRetainingCapacity();
            for (path.items) |node| {
                try path_list.append(node);
            }
        }

        /// Get the next entity in the shortest path from u to v (using ID mapping)
        pub fn nextWithMapping(self: *Self, u: u32, v: u32) u32 {
            var path = std.array_list.Managed(u32).init(self.allocator);
            defer path.deinit();

            const result = self.findPathWithMapping(u, v, &path) catch return std.math.maxInt(u32);
            if (result == null or path.items.len < 2) {
                return std.math.maxInt(u32);
            }
            return path.items[1]; // Second element is next step
        }

        /// Get the next vertex in the shortest path from u to v (direct index)
        pub fn next(self: *Self, u: usize, v: usize) u32 {
            var path = std.array_list.Managed(u32).init(self.allocator);
            defer path.deinit();

            const result = self.findPath(@intCast(u), @intCast(v), &path) catch return std.math.maxInt(u32);
            if (result == null or path.items.len < 2) {
                return std.math.maxInt(u32);
            }
            return path.items[1];
        }

        /// No-op for A* (paths computed on-demand)
        pub fn generate(self: *Self) void {
            _ = self;
            // A* computes paths on-demand, no pre-computation needed
        }
    };
}
