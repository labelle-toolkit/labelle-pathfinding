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
//! - Entity ID mapping for ECS integration
//! - Adjacency list representation (memory efficient for sparse graphs)
//!
//! ## When to use A* vs Floyd-Warshall
//! - **A***: Best for single-source queries, large sparse graphs, real-time games
//! - **Floyd-Warshall**: Best when you need all-pairs paths, dense graphs, or
//!   when paths are queried repeatedly between many node pairs

const std = @import("std");
const heuristics = @import("heuristics.zig");

pub const Heuristic = heuristics.Heuristic;
pub const HeuristicFn = heuristics.HeuristicFn;
pub const Position = heuristics.Position;

const INF = std.math.maxInt(u32);

/// A* pathfinding algorithm with configurable heuristics.
/// Supports both direct vertex indices and entity ID mapping.
pub const AStar = struct {
    const Edge = struct {
        to: u32,
        weight: u64,
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
    positions: std.AutoHashMap(u32, Position),
    ids: std.AutoHashMap(u32, u32),
    reverse_ids: std.AutoHashMap(u32, u32),
    last_key: u32 = 0,
    size: u32 = 100,
    heuristic_type: Heuristic,
    custom_heuristic: ?HeuristicFn,

    pub fn init(allocator: std.mem.Allocator) AStar {
        return .{
            .allocator = allocator,
            .adjacency = .empty,
            .positions = std.AutoHashMap(u32, Position).init(allocator),
            .ids = std.AutoHashMap(u32, u32).init(allocator),
            .reverse_ids = std.AutoHashMap(u32, u32).init(allocator),
            .heuristic_type = .euclidean,
            .custom_heuristic = null,
        };
    }

    pub fn deinit(self: *AStar) void {
        for (self.adjacency.items) |*edges| {
            edges.deinit(self.allocator);
        }
        self.adjacency.deinit(self.allocator);
        self.positions.deinit();
        self.ids.deinit();
        self.reverse_ids.deinit();
    }

    /// Set the heuristic type to use for pathfinding
    pub fn setHeuristic(self: *AStar, heuristic_type: Heuristic) void {
        self.heuristic_type = heuristic_type;
        self.custom_heuristic = null;
    }

    /// Set a custom heuristic function
    pub fn setCustomHeuristic(self: *AStar, heuristic_fn: HeuristicFn) void {
        self.custom_heuristic = heuristic_fn;
    }

    /// Set the position of a node (used for heuristic calculation)
    pub fn setNodePosition(self: *AStar, node: u32, pos: Position) !void {
        try self.positions.put(node, pos);
    }

    /// Set node position using entity ID mapping
    pub fn setNodePositionWithMapping(self: *AStar, entity: u32, pos: Position) !void {
        const internal_id = self.getOrCreateMapping(entity);
        try self.positions.put(internal_id, pos);
    }

    /// Generate a new internal key for entity mapping
    fn newKey(self: *AStar) u32 {
        self.last_key += 1;
        return self.last_key - 1;
    }

    /// Get or create an internal ID mapping for an entity
    fn getOrCreateMapping(self: *AStar, entity: u32) u32 {
        if (self.ids.get(entity)) |id| {
            return id;
        }
        const new_id = self.newKey();
        self.ids.put(entity, new_id) catch |err| {
            std.log.err("Error inserting entity mapping: {}\n", .{err});
            return INF;
        };
        self.reverse_ids.put(new_id, entity) catch |err| {
            std.log.err("Error inserting reverse mapping: {}\n", .{err});
            return INF;
        };
        return new_id;
    }

    /// Resize the graph to support a given number of vertices
    pub fn resize(self: *AStar, size: u32) void {
        self.size = size;
    }

    /// Reset the graph and prepare for new data
    pub fn clean(self: *AStar) !void {
        self.last_key = 0;

        for (self.adjacency.items) |*edges| {
            edges.deinit(self.allocator);
        }
        self.adjacency.clearRetainingCapacity();
        self.positions.clearRetainingCapacity();
        self.ids.clearRetainingCapacity();
        self.reverse_ids.clearRetainingCapacity();

        // Initialize adjacency lists for each vertex
        try self.adjacency.ensureTotalCapacity(self.allocator, self.size);
        for (0..self.size) |_| {
            try self.adjacency.append(self.allocator, .empty);
        }
    }

    /// Add an edge between two vertices with given weight (direct index)
    pub fn addEdge(self: *AStar, u: u32, v: u32, w: u64) void {
        if (u >= self.adjacency.items.len) return;
        self.adjacency.items[u].append(self.allocator, .{ .to = v, .weight = w }) catch |err| {
            std.log.err("Error adding edge: {}\n", .{err});
        };
    }

    /// Add an edge using entity ID mapping (auto-assigns internal indices)
    pub fn addEdgeWithMapping(self: *AStar, u: u32, v: u32, w: u64) void {
        const u_internal = self.getOrCreateMapping(u);
        const v_internal = self.getOrCreateMapping(v);
        self.addEdge(u_internal, v_internal, w);
    }

    /// Calculate heuristic between two internal vertex indices
    fn calculateHeuristic(self: *AStar, from: u32, to: u32) f32 {
        const from_pos = self.positions.get(from) orelse Position{ .x = 0, .y = 0 };
        const to_pos = self.positions.get(to) orelse Position{ .x = 0, .y = 0 };

        if (self.custom_heuristic) |custom| {
            return custom(from_pos, to_pos);
        }
        return heuristics.calculate(self.heuristic_type, from_pos, to_pos);
    }

    /// Run A* algorithm to find shortest path from source to destination.
    /// Returns the path cost, or null if no path exists.
    /// The path is stored in the provided ArrayList.
    pub fn findPath(
        self: *AStar,
        source: u32,
        dest: u32,
        path: *std.array_list.Managed(u32),
    ) !?u64 {
        if (source >= self.adjacency.items.len or dest >= self.adjacency.items.len) {
            return null;
        }

        path.clearRetainingCapacity();

        if (source == dest) {
            try path.append(source);
            return 0;
        }

        var g_score = std.AutoHashMap(u32, u64).init(self.allocator);
        defer g_score.deinit();

        var came_from = std.AutoHashMap(u32, u32).init(self.allocator);
        defer came_from.deinit();

        var closed_set = std.AutoHashMap(u32, void).init(self.allocator);
        defer closed_set.deinit();

        var open_set = std.PriorityQueue(PQNode, void, PQNode.compare).init(self.allocator, {});
        defer open_set.deinit();

        // Initialize source
        try g_score.put(source, 0);
        const h = self.calculateHeuristic(source, dest);
        try open_set.add(.{ .vertex = source, .f_score = h });

        while (open_set.removeOrNull()) |current| {
            if (current.vertex == dest) {
                // Reconstruct path
                var node = dest;
                while (true) {
                    try path.append(node);
                    if (came_from.get(node)) |prev| {
                        node = prev;
                    } else {
                        break;
                    }
                }
                // Reverse to get source -> dest order
                std.mem.reverse(u32, path.items);
                return g_score.get(dest);
            }

            if (closed_set.contains(current.vertex)) {
                continue;
            }
            try closed_set.put(current.vertex, {});

            const current_g = g_score.get(current.vertex) orelse INF;

            // Explore neighbors
            for (self.adjacency.items[current.vertex].items) |edge| {
                if (closed_set.contains(edge.to)) {
                    continue;
                }

                const tentative_g = current_g + edge.weight;
                const neighbor_g = g_score.get(edge.to) orelse INF;

                if (tentative_g < neighbor_g) {
                    try came_from.put(edge.to, current.vertex);
                    try g_score.put(edge.to, tentative_g);

                    const f = @as(f32, @floatFromInt(tentative_g)) + self.calculateHeuristic(edge.to, dest);
                    try open_set.add(.{ .vertex = edge.to, .f_score = f });
                }
            }
        }

        return null; // No path found
    }

    /// Find path using entity ID mapping
    pub fn findPathWithMapping(
        self: *AStar,
        source_entity: u32,
        dest_entity: u32,
        path: *std.array_list.Managed(u32),
    ) !?u64 {
        const source = self.ids.get(source_entity) orelse return null;
        const dest = self.ids.get(dest_entity) orelse return null;

        var internal_path = std.array_list.Managed(u32).init(self.allocator);
        defer internal_path.deinit();

        const cost = try self.findPath(source, dest, &internal_path);

        if (cost != null) {
            path.clearRetainingCapacity();
            for (internal_path.items) |internal_id| {
                const entity = self.reverse_ids.get(internal_id) orelse continue;
                try path.append(entity);
            }
        }

        return cost;
    }

    // ========================================================================
    // DistanceGraph Interface Methods
    // ========================================================================

    /// Check if a path exists between two vertices (direct index)
    pub fn hasPath(self: *AStar, u: usize, v: usize) bool {
        var path = std.array_list.Managed(u32).init(self.allocator);
        defer path.deinit();

        const result = self.findPath(@intCast(u), @intCast(v), &path) catch return false;
        return result != null;
    }

    /// Check if a path exists between two entities (using ID mapping)
    pub fn hasPathWithMapping(self: *AStar, u: u32, v: u32) bool {
        var path = std.array_list.Managed(u32).init(self.allocator);
        defer path.deinit();

        const result = self.findPathWithMapping(u, v, &path) catch return false;
        return result != null;
    }

    /// Get the distance between two vertices (direct index)
    /// Note: This runs A* each time - cache results if needed frequently
    pub fn value(self: *AStar, u: usize, v: usize) u64 {
        var path = std.array_list.Managed(u32).init(self.allocator);
        defer path.deinit();

        const result = self.findPath(@intCast(u), @intCast(v), &path) catch return INF;
        return result orelse INF;
    }

    /// Get the distance between two entities (using ID mapping)
    pub fn valueWithMapping(self: *AStar, u: u32, v: u32) u64 {
        var path = std.array_list.Managed(u32).init(self.allocator);
        defer path.deinit();

        const result = self.findPathWithMapping(u, v, &path) catch return INF;
        return result orelse INF;
    }

    /// Build the path from u to v and store in the provided ArrayList
    pub fn setPathWithMapping(self: *AStar, path_list: *std.array_list.Managed(u32), u: u32, v: u32) !void {
        var path = std.array_list.Managed(u32).init(self.allocator);
        defer path.deinit();

        const result = try self.findPathWithMapping(u, v, &path);
        if (result == null) {
            std.log.err("No path found from {} to {}\n", .{ u, v });
            return;
        }

        path_list.clearRetainingCapacity();
        for (path.items) |node| {
            try path_list.append(node);
        }
    }

    /// Get the next entity in the shortest path from u to v (using ID mapping)
    pub fn nextWithMapping(self: *AStar, u: u32, v: u32) u32 {
        var path = std.array_list.Managed(u32).init(self.allocator);
        defer path.deinit();

        const result = self.findPathWithMapping(u, v, &path) catch return INF;
        if (result == null or path.items.len < 2) {
            return INF;
        }
        return path.items[1]; // Second element is next step
    }

    /// Get the next vertex in the shortest path from u to v (direct index)
    pub fn next(self: *AStar, u: usize, v: usize) u32 {
        var path = std.array_list.Managed(u32).init(self.allocator);
        defer path.deinit();

        const result = self.findPath(@intCast(u), @intCast(v), &path) catch return INF;
        if (result == null or path.items.len < 2) {
            return INF;
        }
        return path.items[1];
    }

    /// No-op for A* (paths computed on-demand)
    pub fn generate(self: *AStar) void {
        _ = self;
        // A* computes paths on-demand, no pre-computation needed
    }
};

// ============================================================================
// Tests
// ============================================================================

test "a_star basic path finding" {
    var astar = AStar.init(std.testing.allocator);
    defer astar.deinit();

    astar.resize(4);
    try astar.clean();

    // Set positions for heuristic
    try astar.setNodePosition(0, .{ .x = 0, .y = 0 });
    try astar.setNodePosition(1, .{ .x = 1, .y = 0 });
    try astar.setNodePosition(2, .{ .x = 2, .y = 0 });
    try astar.setNodePosition(3, .{ .x = 3, .y = 0 });

    // Create a simple graph: 0 -> 1 -> 2 -> 3
    astar.addEdge(0, 1, 1);
    astar.addEdge(1, 2, 1);
    astar.addEdge(2, 3, 1);

    var path = std.array_list.Managed(u32).init(std.testing.allocator);
    defer path.deinit();

    const cost = try astar.findPath(0, 3, &path);

    try std.testing.expect(cost != null);
    try std.testing.expectEqual(@as(u64, 3), cost.?);
    try std.testing.expectEqual(@as(usize, 4), path.items.len);
    try std.testing.expectEqual(@as(u32, 0), path.items[0]);
    try std.testing.expectEqual(@as(u32, 1), path.items[1]);
    try std.testing.expectEqual(@as(u32, 2), path.items[2]);
    try std.testing.expectEqual(@as(u32, 3), path.items[3]);
}

test "a_star with entity mapping" {
    var astar = AStar.init(std.testing.allocator);
    defer astar.deinit();

    astar.resize(3);
    try astar.clean();

    // Use entity IDs 100, 200, 300
    astar.addEdgeWithMapping(100, 200, 1);
    astar.addEdgeWithMapping(200, 300, 1);

    try std.testing.expect(astar.hasPathWithMapping(100, 300));
    try std.testing.expectEqual(@as(u64, 2), astar.valueWithMapping(100, 300));
}

test "a_star no path" {
    var astar = AStar.init(std.testing.allocator);
    defer astar.deinit();

    astar.resize(3);
    try astar.clean();

    // Disconnected graph
    astar.addEdge(0, 1, 1);
    // No edge to 2

    try std.testing.expect(!astar.hasPath(0, 2));
}

test "a_star same source and destination" {
    var astar = AStar.init(std.testing.allocator);
    defer astar.deinit();

    astar.resize(3);
    try astar.clean();

    var path = std.array_list.Managed(u32).init(std.testing.allocator);
    defer path.deinit();

    const cost = try astar.findPath(0, 0, &path);

    try std.testing.expect(cost != null);
    try std.testing.expectEqual(@as(u64, 0), cost.?);
    try std.testing.expectEqual(@as(usize, 1), path.items.len);
}

test "a_star chooses shortest path" {
    var astar = AStar.init(std.testing.allocator);
    defer astar.deinit();

    astar.resize(4);
    try astar.clean();

    // Graph with two paths: 0->1->3 (cost 10) and 0->2->3 (cost 5)
    astar.addEdge(0, 1, 5);
    astar.addEdge(1, 3, 5);
    astar.addEdge(0, 2, 2);
    astar.addEdge(2, 3, 3);

    try std.testing.expectEqual(@as(u64, 5), astar.value(0, 3));
}

test "a_star with manhattan heuristic" {
    var astar = AStar.init(std.testing.allocator);
    defer astar.deinit();

    astar.resize(4);
    try astar.clean();
    astar.setHeuristic(.manhattan);

    // Grid positions
    try astar.setNodePosition(0, .{ .x = 0, .y = 0 });
    try astar.setNodePosition(1, .{ .x = 1, .y = 0 });
    try astar.setNodePosition(2, .{ .x = 0, .y = 1 });
    try astar.setNodePosition(3, .{ .x = 1, .y = 1 });

    // 4-directional grid
    astar.addEdge(0, 1, 1);
    astar.addEdge(0, 2, 1);
    astar.addEdge(1, 3, 1);
    astar.addEdge(2, 3, 1);

    try std.testing.expectEqual(@as(u64, 2), astar.value(0, 3));
}

test "a_star next vertex" {
    var astar = AStar.init(std.testing.allocator);
    defer astar.deinit();

    astar.resize(3);
    try astar.clean();

    astar.addEdge(0, 1, 1);
    astar.addEdge(1, 2, 1);

    try std.testing.expectEqual(@as(u32, 1), astar.next(0, 2));
}

test "a_star path reconstruction with mapping" {
    var astar = AStar.init(std.testing.allocator);
    defer astar.deinit();

    astar.resize(4);
    try astar.clean();

    // Create graph: 10 -> 20 -> 30 -> 40
    astar.addEdgeWithMapping(10, 20, 1);
    astar.addEdgeWithMapping(20, 30, 1);
    astar.addEdgeWithMapping(30, 40, 1);

    var path = std.array_list.Managed(u32).init(std.testing.allocator);
    defer path.deinit();

    try astar.setPathWithMapping(&path, 10, 40);

    try std.testing.expectEqual(@as(usize, 4), path.items.len);
    try std.testing.expectEqual(@as(u32, 10), path.items[0]);
    try std.testing.expectEqual(@as(u32, 20), path.items[1]);
    try std.testing.expectEqual(@as(u32, 30), path.items[2]);
    try std.testing.expectEqual(@as(u32, 40), path.items[3]);
}
