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

const INF: u64 = std.math.maxInt(u64);

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
            std.log.err("Error inserting entity mapping: {any}\n", .{err});
            return std.math.maxInt(u32);
        };
        self.reverse_ids.put(new_id, entity) catch |err| {
            std.log.err("Error inserting reverse mapping: {any}\n", .{err});
            return std.math.maxInt(u32);
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
        if (u >= self.adjacency.items.len or v >= self.adjacency.items.len) return;
        self.adjacency.items[u].append(self.allocator, .{ .to = v, .weight = w }) catch |err| {
            std.log.err("Error adding edge: {any}\n", .{err});
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

        const result = self.findPathWithMapping(u, v, &path) catch return std.math.maxInt(u32);
        if (result == null or path.items.len < 2) {
            return std.math.maxInt(u32);
        }
        return path.items[1]; // Second element is next step
    }

    /// Get the next vertex in the shortest path from u to v (direct index)
    pub fn next(self: *AStar, u: usize, v: usize) u32 {
        var path = std.array_list.Managed(u32).init(self.allocator);
        defer path.deinit();

        const result = self.findPath(@intCast(u), @intCast(v), &path) catch return std.math.maxInt(u32);
        if (result == null or path.items.len < 2) {
            return std.math.maxInt(u32);
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
// A* with Hooks
// ============================================================================

const hooks = @import("hooks.zig");

/// A* pathfinding algorithm with hook dispatching.
/// Wraps the base AStar and emits hooks at lifecycle points.
///
/// Example:
/// ```zig
/// const MyHooks = struct {
///     pub fn path_found(payload: hooks.HookPayload) void {
///         std.log.info("Path found!", .{});
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

        // Re-export types from base
        pub const Edge = AStar.Edge;
        pub const PQNode = AStar.PQNode;

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

        pub fn addEdge(self: *Self, u: u32, v: u32, w: u64) void {
            self.base.addEdge(u, v, w);
        }

        pub fn addEdgeWithMapping(self: *Self, u: u32, v: u32, w: u64) void {
            self.base.addEdgeWithMapping(u, v, w);
        }

        pub fn generate(self: *Self) void {
            self.base.generate();
        }

        // ====================================================================
        // Core algorithm (no hooks)
        // ====================================================================

        /// Internal result type for findPathCore
        const FindPathResult = struct {
            cost: ?u64,
            nodes_explored: u32,
        };

        /// Core A* algorithm without hook dispatching.
        /// Used internally by findPath and findPathWithMapping to avoid double hook emission.
        fn findPathCore(
            self: *Self,
            source: u32,
            dest: u32,
            path: *std.array_list.Managed(u32),
        ) !FindPathResult {
            var nodes_explored: u32 = 0;

            if (source >= self.base.adjacency.items.len or dest >= self.base.adjacency.items.len) {
                return .{ .cost = null, .nodes_explored = 0 };
            }

            path.clearRetainingCapacity();

            if (source == dest) {
                try path.append(source);
                return .{ .cost = 0, .nodes_explored = 1 };
            }

            var g_score = std.AutoHashMap(u32, u64).init(self.base.allocator);
            defer g_score.deinit();

            var came_from = std.AutoHashMap(u32, u32).init(self.base.allocator);
            defer came_from.deinit();

            var closed_set = std.AutoHashMap(u32, void).init(self.base.allocator);
            defer closed_set.deinit();

            var open_set = std.PriorityQueue(AStar.PQNode, void, AStar.PQNode.compare).init(self.base.allocator, {});
            defer open_set.deinit();

            // Initialize source
            try g_score.put(source, 0);
            const h = self.base.calculateHeuristic(source, dest);
            try open_set.add(.{ .vertex = source, .f_score = h });

            while (open_set.removeOrNull()) |current| {
                nodes_explored += 1;

                const current_g = g_score.get(current.vertex) orelse INF;

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
                    std.mem.reverse(u32, path.items);

                    const cost = g_score.get(dest) orelse unreachable;
                    return .{ .cost = cost, .nodes_explored = nodes_explored };
                }

                if (closed_set.contains(current.vertex)) {
                    continue;
                }
                try closed_set.put(current.vertex, {});

                // Explore neighbors
                for (self.base.adjacency.items[current.vertex].items) |edge| {
                    if (closed_set.contains(edge.to)) {
                        continue;
                    }

                    const tentative_g = current_g + edge.weight;
                    const neighbor_g = g_score.get(edge.to) orelse INF;

                    if (tentative_g < neighbor_g) {
                        try came_from.put(edge.to, current.vertex);
                        try g_score.put(edge.to, tentative_g);

                        const f = @as(f32, @floatFromInt(tentative_g)) + self.base.calculateHeuristic(edge.to, dest);
                        try open_set.add(.{ .vertex = edge.to, .f_score = f });
                    }
                }
            }

            return .{ .cost = null, .nodes_explored = nodes_explored };
        }

        // ====================================================================
        // Methods with hook dispatching
        // ====================================================================

        /// Run A* algorithm with hook dispatching.
        /// Emits path_requested, node_visited, path_found/no_path_found, and search_complete hooks.
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

            var nodes_explored: u32 = 0;

            if (source >= self.base.adjacency.items.len or dest >= self.base.adjacency.items.len) {
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
                return null;
            }

            path.clearRetainingCapacity();

            if (source == dest) {
                try path.append(source);
                Dispatcher.emit(.{ .node_visited = .{
                    .node = source,
                    .g_score = 0,
                    .f_score = 0,
                    .from_node = null,
                } });
                Dispatcher.emit(.{ .path_found = .{
                    .source = source,
                    .dest = dest,
                    .cost = 0,
                    .path_length = 1,
                } });
                Dispatcher.emit(.{ .search_complete = .{
                    .source = source,
                    .dest = dest,
                    .success = true,
                    .nodes_explored = 1,
                    .path_length = 1,
                    .cost = 0,
                } });
                return 0;
            }

            var g_score = std.AutoHashMap(u32, u64).init(self.base.allocator);
            defer g_score.deinit();

            var came_from = std.AutoHashMap(u32, u32).init(self.base.allocator);
            defer came_from.deinit();

            var closed_set = std.AutoHashMap(u32, void).init(self.base.allocator);
            defer closed_set.deinit();

            var open_set = std.PriorityQueue(AStar.PQNode, void, AStar.PQNode.compare).init(self.base.allocator, {});
            defer open_set.deinit();

            // Initialize source
            try g_score.put(source, 0);
            const h = self.base.calculateHeuristic(source, dest);
            try open_set.add(.{ .vertex = source, .f_score = h });

            while (open_set.removeOrNull()) |current| {
                nodes_explored += 1;

                const current_g = g_score.get(current.vertex) orelse INF;

                // Emit node_visited hook
                Dispatcher.emit(.{ .node_visited = .{
                    .node = current.vertex,
                    .g_score = current_g,
                    .f_score = current.f_score,
                    .from_node = came_from.get(current.vertex),
                } });

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
                    std.mem.reverse(u32, path.items);

                    const cost = g_score.get(dest) orelse unreachable;
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
                        .nodes_explored = nodes_explored,
                        .path_length = path.items.len,
                        .cost = cost,
                    } });
                    return cost;
                }

                if (closed_set.contains(current.vertex)) {
                    continue;
                }
                try closed_set.put(current.vertex, {});

                // Explore neighbors
                for (self.base.adjacency.items[current.vertex].items) |edge| {
                    if (closed_set.contains(edge.to)) {
                        continue;
                    }

                    const tentative_g = current_g + edge.weight;
                    const neighbor_g = g_score.get(edge.to) orelse INF;

                    if (tentative_g < neighbor_g) {
                        try came_from.put(edge.to, current.vertex);
                        try g_score.put(edge.to, tentative_g);

                        const f = @as(f32, @floatFromInt(tentative_g)) + self.base.calculateHeuristic(edge.to, dest);
                        try open_set.add(.{ .vertex = edge.to, .f_score = f });
                    }
                }
            }

            // No path found
            Dispatcher.emit(.{ .no_path_found = .{
                .source = source,
                .dest = dest,
                .nodes_explored = nodes_explored,
            } });
            Dispatcher.emit(.{ .search_complete = .{
                .source = source,
                .dest = dest,
                .success = false,
                .nodes_explored = nodes_explored,
                .path_length = 0,
                .cost = null,
            } });
            return null;
        }

        /// Find path using entity ID mapping with hook dispatching.
        /// Hooks are emitted with entity IDs, not internal node indices.
        pub fn findPathWithMapping(
            self: *Self,
            source_entity: u32,
            dest_entity: u32,
            path: *std.array_list.Managed(u32),
        ) !?u64 {
            // Emit path_requested with entity IDs
            Dispatcher.emit(.{ .path_requested = .{
                .source = source_entity,
                .dest = dest_entity,
            } });

            const source = self.base.ids.get(source_entity) orelse {
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
                return null;
            };
            const dest = self.base.ids.get(dest_entity) orelse {
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
                return null;
            };

            var internal_path = std.array_list.Managed(u32).init(self.base.allocator);
            defer internal_path.deinit();

            // Use core algorithm without hooks to avoid double emission
            const result = try self.findPathCore(source, dest, &internal_path);

            if (result.cost) |cost| {
                path.clearRetainingCapacity();
                for (internal_path.items) |internal_id| {
                    const entity = self.base.reverse_ids.get(internal_id) orelse continue;
                    try path.append(entity);
                }

                // Emit hooks with entity IDs
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
                    .nodes_explored = result.nodes_explored,
                    .path_length = path.items.len,
                    .cost = cost,
                } });
                return cost;
            } else {
                Dispatcher.emit(.{ .no_path_found = .{
                    .source = source_entity,
                    .dest = dest_entity,
                    .nodes_explored = result.nodes_explored,
                } });
                Dispatcher.emit(.{ .search_complete = .{
                    .source = source_entity,
                    .dest = dest_entity,
                    .success = false,
                    .nodes_explored = result.nodes_explored,
                    .path_length = 0,
                    .cost = null,
                } });
                return null;
            }
        }

        // ====================================================================
        // DistanceGraph Interface Methods (delegated with hooks on findPath)
        // ====================================================================

        pub fn hasPath(self: *Self, u: usize, v: usize) bool {
            var path = std.array_list.Managed(u32).init(self.base.allocator);
            defer path.deinit();

            const result = self.findPath(@intCast(u), @intCast(v), &path) catch return false;
            return result != null;
        }

        pub fn hasPathWithMapping(self: *Self, u: u32, v: u32) bool {
            var path = std.array_list.Managed(u32).init(self.base.allocator);
            defer path.deinit();

            const result = self.findPathWithMapping(u, v, &path) catch return false;
            return result != null;
        }

        pub fn value(self: *Self, u: usize, v: usize) u64 {
            var path = std.array_list.Managed(u32).init(self.base.allocator);
            defer path.deinit();

            const result = self.findPath(@intCast(u), @intCast(v), &path) catch return INF;
            return result orelse INF;
        }

        pub fn valueWithMapping(self: *Self, u: u32, v: u32) u64 {
            var path = std.array_list.Managed(u32).init(self.base.allocator);
            defer path.deinit();

            const result = self.findPathWithMapping(u, v, &path) catch return INF;
            return result orelse INF;
        }

        pub fn setPathWithMapping(self: *Self, path_list: *std.array_list.Managed(u32), u: u32, v: u32) !void {
            var path = std.array_list.Managed(u32).init(self.base.allocator);
            defer path.deinit();

            const result = try self.findPathWithMapping(u, v, &path);
            if (result == null) {
                return;
            }

            path_list.clearRetainingCapacity();
            for (path.items) |node| {
                try path_list.append(node);
            }
        }

        pub fn nextWithMapping(self: *Self, u: u32, v: u32) u32 {
            var path = std.array_list.Managed(u32).init(self.base.allocator);
            defer path.deinit();

            const result = self.findPathWithMapping(u, v, &path) catch return std.math.maxInt(u32);
            if (result == null or path.items.len < 2) {
                return std.math.maxInt(u32);
            }
            return path.items[1];
        }

        pub fn next(self: *Self, u: usize, v: usize) u32 {
            var path = std.array_list.Managed(u32).init(self.base.allocator);
            defer path.deinit();

            const result = self.findPath(@intCast(u), @intCast(v), &path) catch return std.math.maxInt(u32);
            if (result == null or path.items.len < 2) {
                return std.math.maxInt(u32);
            }
            return path.items[1];
        }
    };
}
