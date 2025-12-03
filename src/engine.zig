//! PathfindingEngine - Self-contained pathfinding system
//!
//! A complete pathfinding solution that owns entity positions internally.
//! The game queries the engine for positions rather than owning them directly.
//!
//! ## Features
//! - Comptime-configurable entity and context types
//! - Internal position management (PositionPF)
//! - Graph building with omnidirectional or directional connection modes
//! - Floyd-Warshall precomputed shortest paths
//! - QuadTree-backed spatial queries
//! - Callbacks for path events (node reached, path completed, path blocked)

const std = @import("std");
const quad_tree = @import("quad_tree.zig");
const QuadTree = quad_tree.QuadTree;
const Rectangle = quad_tree.Rectangle;
const EntityPoint = quad_tree.EntityPoint;
const Point2D = quad_tree.Point2D;
const FloydWarshall = @import("floyd_warshall.zig").FloydWarshall;

/// Log level for controlling pathfinding engine verbosity
pub const LogLevel = enum {
    /// Disable all logging
    none,
    /// Critical failures only
    err,
    /// Recoverable errors and warnings
    warning,
    /// Path requests, entity registration, graph rebuilds
    info,
    /// Detailed operational logs: path steps, stair queues, spatial updates
    debug,

    /// Check if this log level allows messages at the given level
    pub fn allows(self: LogLevel, level: LogLevel) bool {
        return @intFromEnum(self) >= @intFromEnum(level);
    }
};

/// Node identifier type
pub const NodeId = u32;

/// Stair mode for vertical connection traffic control
pub const StairMode = enum {
    /// Not a stair - no vertical connections (default)
    none,
    /// Multi-lane stair - unlimited concurrent usage in any direction
    all,
    /// Directional stair - entities can only use if another is going same direction (or empty)
    direction,
    /// Single-file stair - only one entity can use at a time
    single,
};

/// Vertical direction for stair traversal
pub const VerticalDirection = enum {
    up,
    down,
};

/// Connection mode for automatic graph building
pub const ConnectionMode = union(enum) {
    /// Top-down games: connect to N closest neighbors in any direction
    omnidirectional: struct {
        max_distance: f32,
        max_connections: u8,
    },
    /// Platformers: connect in 4 cardinal directions
    directional: struct {
        horizontal_range: f32,
        vertical_range: f32,
    },
    /// Building games: horizontal connections + stair-based vertical connections
    building: struct {
        horizontal_range: f32,
        floor_height: f32,
    },
};

/// Node data stored in the graph
pub const NodeData = struct {
    x: f32,
    y: f32,
    stair_mode: StairMode = .none,
};

/// Point with ID for bulk node creation
pub const NodePoint = struct {
    id: NodeId,
    x: f32,
    y: f32,
};

/// Pathfinding engine with comptime configuration
pub fn PathfindingEngine(comptime Config: type) type {
    const Entity = Config.Entity;
    const Context = Config.Context;
    // Extract log_level from Config, defaulting to .none (silent)
    const log_level: LogLevel = if (@hasDecl(Config, "log_level")) Config.log_level else .none;

    return struct {
        const Self = @This();

        // =======================================================
        // Logging
        // =======================================================

        fn logErr(comptime fmt: []const u8, args: anytype) void {
            if (comptime log_level.allows(.err)) {
                std.log.scoped(.pathfinding).err(fmt, args);
            }
        }

        fn logWarn(comptime fmt: []const u8, args: anytype) void {
            if (comptime log_level.allows(.warning)) {
                std.log.scoped(.pathfinding).warn(fmt, args);
            }
        }

        fn logInfo(comptime fmt: []const u8, args: anytype) void {
            if (comptime log_level.allows(.info)) {
                std.log.scoped(.pathfinding).info(fmt, args);
            }
        }

        fn logDebug(comptime fmt: []const u8, args: anytype) void {
            if (comptime log_level.allows(.debug)) {
                std.log.scoped(.pathfinding).debug(fmt, args);
            }
        }

        /// Position data owned by pathfinding
        pub const PositionPF = struct {
            x: f32,
            y: f32,
            current_node: NodeId,
            edge_progress: f32,
            target_node: ?NodeId,
            speed: f32,
            path: std.ArrayListUnmanaged(NodeId),
            path_index: usize,
            /// Node the entity is waiting to enter (stair)
            waiting_for_stair: ?NodeId = null,
            /// Node where entity is waiting (dispersal spot)
            waiting_at_node: ?NodeId = null,
            /// Direction entity wants to travel on stair
            waiting_direction: ?VerticalDirection = null,
            /// The stair node this entity is currently using (for exit tracking)
            using_stair: ?NodeId = null,
        };

        /// Directional edges for platformer-style connections
        pub const DirectionalEdges = struct {
            left: ?NodeId = null,
            right: ?NodeId = null,
            up: ?NodeId = null,
            down: ?NodeId = null,
        };

        /// Runtime state for stair traffic management
        pub const StairState = struct {
            mode: StairMode,
            current_direction: ?VerticalDirection = null,
            users_count: u32 = 0,
            waiting_queue: std.ArrayListUnmanaged(Entity) = .{},

            pub fn canEnter(self: *const StairState, dir: VerticalDirection) bool {
                return switch (self.mode) {
                    .none => false,
                    .all => true,
                    .direction => self.users_count == 0 or self.current_direction == dir,
                    .single => self.users_count == 0,
                };
            }

            pub fn enter(self: *StairState, dir: VerticalDirection) void {
                self.users_count += 1;
                if (self.mode == .direction and self.current_direction == null) {
                    self.current_direction = dir;
                }
            }

            pub fn exit(self: *StairState) void {
                if (self.users_count > 0) {
                    self.users_count -= 1;
                }
                if (self.users_count == 0) {
                    self.current_direction = null;
                }
            }

            pub fn deinit(self: *StairState, allocator: std.mem.Allocator) void {
                self.waiting_queue.deinit(allocator);
            }
        };

        /// Waiting area for entities queued at a stair
        pub const WaitingArea = struct {
            stair_node: NodeId,
            waiting_spots: std.ArrayListUnmanaged(NodeId) = .{},
            /// Tracks which spots are occupied (spot NodeId -> occupying Entity)
            occupied_spots: std.AutoHashMap(NodeId, Entity) = undefined,

            pub fn init(allocator: std.mem.Allocator, stair_node: NodeId) WaitingArea {
                return .{
                    .stair_node = stair_node,
                    .occupied_spots = std.AutoHashMap(NodeId, Entity).init(allocator),
                };
            }

            pub fn deinit(self: *WaitingArea, allocator: std.mem.Allocator) void {
                self.waiting_spots.deinit(allocator);
                self.occupied_spots.deinit();
            }

            pub fn occupySpot(self: *WaitingArea, spot: NodeId, entity: Entity) void {
                self.occupied_spots.put(spot, entity) catch {};
            }

            pub fn releaseSpot(self: *WaitingArea, spot: NodeId) void {
                _ = self.occupied_spots.remove(spot);
            }

            pub fn findAvailableSpot(self: *WaitingArea) ?NodeId {
                for (self.waiting_spots.items) |spot| {
                    if (!self.occupied_spots.contains(spot)) {
                        return spot;
                    }
                }
                return null;
            }
        };

        /// Event types for deferred callback invocation
        const PathEvent = struct {
            entity: Entity,
            node: NodeId,
        };

        // === Internal State ===
        allocator: std.mem.Allocator,

        // Graph
        nodes: std.AutoHashMap(NodeId, NodeData),
        edges: std.AutoHashMap(NodeId, std.ArrayListUnmanaged(NodeId)),
        directional_edges: std.AutoHashMap(NodeId, DirectionalEdges),
        node_spatial: QuadTree(NodeId),
        floyd_warshall: FloydWarshall,
        next_node_id: NodeId = 0,

        // Entities
        entities: std.AutoHashMap(Entity, PositionPF),
        entity_spatial: QuadTree(Entity),

        // Stair management
        stair_states: std.AutoHashMap(NodeId, StairState),
        waiting_areas: std.AutoHashMap(NodeId, WaitingArea),

        // === Callbacks ===
        on_node_reached: ?*const fn (Context, Entity, NodeId) void = null,
        on_path_completed: ?*const fn (Context, Entity, NodeId) void = null,
        on_path_blocked: ?*const fn (Context, Entity, NodeId) void = null,

        // Event buffers for deferred callbacks
        node_reached_events: std.ArrayListUnmanaged(PathEvent),
        path_completed_events: std.ArrayListUnmanaged(PathEvent),
        path_blocked_events: std.ArrayListUnmanaged(PathEvent),

        pub fn init(allocator: std.mem.Allocator) !Self {
            return .{
                .allocator = allocator,
                .nodes = std.AutoHashMap(NodeId, NodeData).init(allocator),
                .edges = std.AutoHashMap(NodeId, std.ArrayListUnmanaged(NodeId)).init(allocator),
                .directional_edges = std.AutoHashMap(NodeId, DirectionalEdges).init(allocator),
                .node_spatial = try QuadTree(NodeId).init(allocator, .{ .x = -50000, .y = -50000, .width = 100000, .height = 100000 }),
                .floyd_warshall = FloydWarshall.init(allocator),
                .entities = std.AutoHashMap(Entity, PositionPF).init(allocator),
                .entity_spatial = try QuadTree(Entity).init(allocator, .{ .x = -50000, .y = -50000, .width = 100000, .height = 100000 }),
                .stair_states = std.AutoHashMap(NodeId, StairState).init(allocator),
                .waiting_areas = std.AutoHashMap(NodeId, WaitingArea).init(allocator),
                .node_reached_events = .{},
                .path_completed_events = .{},
                .path_blocked_events = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            // Clean up entity paths
            var entity_iter = self.entities.valueIterator();
            while (entity_iter.next()) |pos| {
                pos.path.deinit(self.allocator);
            }
            self.entities.deinit();

            // Clean up edges
            var edge_iter = self.edges.valueIterator();
            while (edge_iter.next()) |edge_list| {
                edge_list.deinit(self.allocator);
            }
            self.edges.deinit();

            // Clean up stair states
            var stair_iter = self.stair_states.valueIterator();
            while (stair_iter.next()) |state| {
                state.deinit(self.allocator);
            }
            self.stair_states.deinit();

            // Clean up waiting areas
            var waiting_iter = self.waiting_areas.valueIterator();
            while (waiting_iter.next()) |area| {
                area.deinit(self.allocator);
            }
            self.waiting_areas.deinit();

            self.nodes.deinit();
            self.directional_edges.deinit();
            self.node_spatial.deinit();
            self.floyd_warshall.deinit();
            self.entity_spatial.deinit();
            self.node_reached_events.deinit(self.allocator);
            self.path_completed_events.deinit(self.allocator);
            self.path_blocked_events.deinit(self.allocator);
        }

        // =======================================================
        // Graph Building
        // =======================================================

        /// Add a node at the given position with optional stair mode
        pub fn addNode(self: *Self, id: NodeId, x: f32, y: f32) !void {
            try self.addNodeWithStairMode(id, x, y, .none);
        }

        /// Add a node with a specific stair mode
        pub fn addNodeWithStairMode(self: *Self, id: NodeId, x: f32, y: f32, stair_mode: StairMode) !void {
            try self.nodes.put(id, .{ .x = x, .y = y, .stair_mode = stair_mode });
            _ = self.node_spatial.insert(.{ .id = id, .x = x, .y = y });
            if (id >= self.next_node_id) {
                self.next_node_id = id + 1;
            }
            // Initialize stair state if this is a stair node
            if (stair_mode != .none) {
                try self.stair_states.put(id, .{ .mode = stair_mode });
            }
        }

        /// Add a node and return the auto-generated ID
        pub fn addNodeAuto(self: *Self, x: f32, y: f32) !NodeId {
            return self.addNodeAutoWithStairMode(x, y, .none);
        }

        /// Add a node with stair mode and return the auto-generated ID
        pub fn addNodeAutoWithStairMode(self: *Self, x: f32, y: f32, stair_mode: StairMode) !NodeId {
            const id = self.next_node_id;
            try self.addNodeWithStairMode(id, x, y, stair_mode);
            return id;
        }

        /// Remove a node from the graph
        pub fn removeNode(self: *Self, id: NodeId) void {
            _ = self.nodes.remove(id);
            if (self.edges.fetchRemove(id)) |removed| {
                var edge_list = removed.value;
                edge_list.deinit(self.allocator);
            }
            _ = self.directional_edges.remove(id);
            _ = self.node_spatial.remove(id);
            // Clean up stair state if present
            if (self.stair_states.fetchRemove(id)) |removed| {
                var state = removed.value;
                state.deinit(self.allocator);
            }
            if (self.waiting_areas.fetchRemove(id)) |removed| {
                var area = removed.value;
                area.deinit(self.allocator);
            }
        }

        /// Add multiple nodes from an array of points
        pub fn addNodesFromPoints(self: *Self, points: []const NodePoint) !void {
            for (points) |p| {
                try self.addNode(p.id, p.x, p.y);
            }
        }

        /// Clear all nodes and edges
        pub fn clearGraph(self: *Self) void {
            var edge_iter = self.edges.valueIterator();
            while (edge_iter.next()) |edge_list| {
                edge_list.deinit(self.allocator);
            }
            self.edges.clearRetainingCapacity();
            self.nodes.clearRetainingCapacity();
            self.directional_edges.clearRetainingCapacity();
            // Clear stair states
            var stair_iter = self.stair_states.valueIterator();
            while (stair_iter.next()) |state| {
                state.deinit(self.allocator);
            }
            self.stair_states.clearRetainingCapacity();
            // Clear waiting areas
            var waiting_iter = self.waiting_areas.valueIterator();
            while (waiting_iter.next()) |area| {
                area.deinit(self.allocator);
            }
            self.waiting_areas.clearRetainingCapacity();
            self.node_spatial.reset();
            self.next_node_id = 0;
        }

        /// Clear all edges and create new connections based on mode
        pub fn connectNodes(self: *Self, mode: ConnectionMode) !void {
            // Clear existing edges
            var edge_iter = self.edges.valueIterator();
            while (edge_iter.next()) |edge_list| {
                edge_list.deinit(self.allocator);
            }
            self.edges.clearRetainingCapacity();
            self.directional_edges.clearRetainingCapacity();

            // Rebuild node spatial index
            var points: std.ArrayListUnmanaged(Point2D) = .{};
            defer points.deinit(self.allocator);

            var node_iter = self.nodes.iterator();
            while (node_iter.next()) |entry| {
                try points.append(self.allocator, Point2D{ .x = entry.value_ptr.x, .y = entry.value_ptr.y });
            }

            try self.node_spatial.resetWithBoundaries(points.items);

            node_iter = self.nodes.iterator();
            while (node_iter.next()) |entry| {
                _ = self.node_spatial.insert(.{ .id = entry.key_ptr.*, .x = entry.value_ptr.x, .y = entry.value_ptr.y });
            }

            // Connect based on mode
            switch (mode) {
                .omnidirectional => |config| try self.connectOmnidirectional(config.max_distance, config.max_connections),
                .directional => |config| try self.connectDirectional(config.horizontal_range, config.vertical_range),
                .building => |config| try self.connectBuilding(config.horizontal_range, config.floor_height),
            }
        }

        fn connectOmnidirectional(self: *Self, max_distance: f32, max_connections: u8) !void {
            var buffer: std.ArrayListUnmanaged(EntityPoint(NodeId)) = .{};
            defer buffer.deinit(self.allocator);

            var node_iter = self.nodes.iterator();
            while (node_iter.next()) |entry| {
                const id = entry.key_ptr.*;
                const node = entry.value_ptr.*;

                buffer.clearRetainingCapacity();
                try self.node_spatial.queryRadius(node.x, node.y, max_distance, &buffer);

                // Sort by distance
                const SortContext = struct {
                    x: f32,
                    y: f32,

                    pub fn lessThan(ctx: @This(), a: EntityPoint(NodeId), b: EntityPoint(NodeId)) bool {
                        const dist_a = (a.x - ctx.x) * (a.x - ctx.x) + (a.y - ctx.y) * (a.y - ctx.y);
                        const dist_b = (b.x - ctx.x) * (b.x - ctx.x) + (b.y - ctx.y) * (b.y - ctx.y);
                        return dist_a < dist_b;
                    }
                };

                std.mem.sort(EntityPoint(NodeId), buffer.items, SortContext{ .x = node.x, .y = node.y }, SortContext.lessThan);

                // Connect to closest N neighbors (excluding self)
                var connected: u8 = 0;
                for (buffer.items) |neighbor| {
                    if (neighbor.id == id) continue;
                    if (connected >= max_connections) break;

                    try self.addEdgeInternal(id, neighbor.id);
                    connected += 1;
                }
            }
        }

        fn connectDirectional(self: *Self, horizontal_range: f32, vertical_range: f32) !void {
            var buffer: std.ArrayListUnmanaged(EntityPoint(NodeId)) = .{};
            defer buffer.deinit(self.allocator);

            var node_iter = self.nodes.iterator();
            while (node_iter.next()) |entry| {
                const id = entry.key_ptr.*;
                const node = entry.value_ptr.*;

                var dir_edges = DirectionalEdges{};

                // Right
                buffer.clearRetainingCapacity();
                try self.node_spatial.queryRect(.{
                    .x = node.x + 1,
                    .y = node.y - 5,
                    .width = horizontal_range,
                    .height = 10,
                }, &buffer);
                dir_edges.right = self.findClosest(id, node, buffer.items);

                // Left
                buffer.clearRetainingCapacity();
                try self.node_spatial.queryRect(.{
                    .x = node.x - horizontal_range - 1,
                    .y = node.y - 5,
                    .width = horizontal_range,
                    .height = 10,
                }, &buffer);
                dir_edges.left = self.findClosest(id, node, buffer.items);

                // Down
                buffer.clearRetainingCapacity();
                try self.node_spatial.queryRect(.{
                    .x = node.x - 5,
                    .y = node.y + 1,
                    .width = 10,
                    .height = vertical_range,
                }, &buffer);
                dir_edges.down = self.findClosest(id, node, buffer.items);

                // Up
                buffer.clearRetainingCapacity();
                try self.node_spatial.queryRect(.{
                    .x = node.x - 5,
                    .y = node.y - vertical_range - 1,
                    .width = 10,
                    .height = vertical_range,
                }, &buffer);
                dir_edges.up = self.findClosest(id, node, buffer.items);

                try self.directional_edges.put(id, dir_edges);

                // Also add to general edges for pathfinding
                if (dir_edges.right) |r| try self.addEdgeInternal(id, r);
                if (dir_edges.left) |l| try self.addEdgeInternal(id, l);
                if (dir_edges.up) |u| try self.addEdgeInternal(id, u);
                if (dir_edges.down) |d| try self.addEdgeInternal(id, d);
            }
        }

        /// Building mode: horizontal connections + stair-based vertical connections
        /// Vertical connections only occur between stair nodes
        fn connectBuilding(self: *Self, horizontal_range: f32, floor_height: f32) !void {
            var buffer: std.ArrayListUnmanaged(EntityPoint(NodeId)) = .{};
            defer buffer.deinit(self.allocator);

            var node_iter = self.nodes.iterator();
            while (node_iter.next()) |entry| {
                const id = entry.key_ptr.*;
                const node = entry.value_ptr.*;

                var dir_edges = DirectionalEdges{};

                // Right - always connect horizontally
                buffer.clearRetainingCapacity();
                try self.node_spatial.queryRect(.{
                    .x = node.x + 1,
                    .y = node.y - 5,
                    .width = horizontal_range,
                    .height = 10,
                }, &buffer);
                dir_edges.right = self.findClosest(id, node, buffer.items);

                // Left - always connect horizontally
                buffer.clearRetainingCapacity();
                try self.node_spatial.queryRect(.{
                    .x = node.x - horizontal_range - 1,
                    .y = node.y - 5,
                    .width = horizontal_range,
                    .height = 10,
                }, &buffer);
                dir_edges.left = self.findClosest(id, node, buffer.items);

                // Down - only connect if current node is a stair
                if (node.stair_mode != .none) {
                    buffer.clearRetainingCapacity();
                    try self.node_spatial.queryRect(.{
                        .x = node.x - 5,
                        .y = node.y + 1,
                        .width = 10,
                        .height = floor_height,
                    }, &buffer);
                    // Find closest stair node below
                    dir_edges.down = self.findClosestStair(id, node, buffer.items);
                }

                // Up - only connect if current node is a stair
                // Both nodes must be stairs for bidirectional vertical connection
                if (node.stair_mode != .none) {
                    buffer.clearRetainingCapacity();
                    try self.node_spatial.queryRect(.{
                        .x = node.x - 5,
                        .y = node.y - floor_height - 1,
                        .width = 10,
                        .height = floor_height,
                    }, &buffer);
                    // Find closest stair node above
                    dir_edges.up = self.findClosestStair(id, node, buffer.items);
                }

                try self.directional_edges.put(id, dir_edges);

                // Also add to general edges for pathfinding
                if (dir_edges.right) |r| try self.addEdgeInternal(id, r);
                if (dir_edges.left) |l| try self.addEdgeInternal(id, l);
                if (dir_edges.up) |u| try self.addEdgeInternal(id, u);
                if (dir_edges.down) |d| try self.addEdgeInternal(id, d);
            }
        }

        fn findClosest(self: *Self, exclude_id: NodeId, from: NodeData, candidates: []const EntityPoint(NodeId)) ?NodeId {
            _ = self;
            var closest: ?NodeId = null;
            var closest_dist: f32 = std.math.inf(f32);

            for (candidates) |c| {
                if (c.id == exclude_id) continue;
                const dx = c.x - from.x;
                const dy = c.y - from.y;
                const dist = dx * dx + dy * dy;
                if (dist < closest_dist) {
                    closest_dist = dist;
                    closest = c.id;
                }
            }

            return closest;
        }

        /// Find closest node that is a stair (has stair_mode != .none)
        fn findClosestStair(self: *Self, exclude_id: NodeId, from: NodeData, candidates: []const EntityPoint(NodeId)) ?NodeId {
            var closest: ?NodeId = null;
            var closest_dist: f32 = std.math.inf(f32);

            for (candidates) |c| {
                if (c.id == exclude_id) continue;
                // Check if this node is a stair
                const candidate_node = self.nodes.get(c.id) orelse continue;
                if (candidate_node.stair_mode == .none) continue;

                const dx = c.x - from.x;
                const dy = c.y - from.y;
                const dist = dx * dx + dy * dy;
                if (dist < closest_dist) {
                    closest_dist = dist;
                    closest = c.id;
                }
            }

            return closest;
        }

        fn addEdgeInternal(self: *Self, from: NodeId, to: NodeId) !void {
            const entry = try self.edges.getOrPut(from);
            if (!entry.found_existing) {
                entry.value_ptr.* = .{};
            }
            // Check if edge already exists
            for (entry.value_ptr.items) |existing| {
                if (existing == to) return;
            }
            try entry.value_ptr.append(self.allocator, to);
        }

        /// Manually add an edge (use after connectNodes for special cases)
        pub fn addEdge(self: *Self, from: NodeId, to: NodeId, bidirectional: bool) !void {
            try self.addEdgeInternal(from, to);
            if (bidirectional) {
                try self.addEdgeInternal(to, from);
            }
        }

        /// Remove an edge
        pub fn removeEdge(self: *Self, from: NodeId, to: NodeId) void {
            if (self.edges.getPtr(from)) |edge_list| {
                var i: usize = 0;
                while (i < edge_list.items.len) {
                    if (edge_list.items[i] == to) {
                        _ = edge_list.swapRemove(i);
                    } else {
                        i += 1;
                    }
                }
            }
        }

        /// Rebuild Floyd-Warshall shortest paths (call after graph changes)
        pub fn rebuildPaths(self: *Self) !void {
            const node_count = self.nodes.count();
            if (node_count == 0) return;

            logInfo("Rebuilding paths for {} nodes", .{node_count});

            self.floyd_warshall.resize(@intCast(node_count));
            try self.floyd_warshall.clean();

            // Add all edges to Floyd-Warshall
            var edge_iter = self.edges.iterator();
            while (edge_iter.next()) |entry| {
                const from = entry.key_ptr.*;
                for (entry.value_ptr.items) |to| {
                    // Use distance as weight
                    const from_node = self.nodes.get(from) orelse continue;
                    const to_node = self.nodes.get(to) orelse continue;
                    const dx = to_node.x - from_node.x;
                    const dy = to_node.y - from_node.y;
                    const dist: u64 = @intFromFloat(@round(@sqrt(dx * dx + dy * dy)));
                    self.floyd_warshall.addEdgeWithMapping(from, to, @max(1, dist));
                }
            }

            self.floyd_warshall.generate();
        }

        // =======================================================
        // Entity Management
        // =======================================================

        /// Register an entity at a position (snaps to nearest node)
        pub fn registerEntity(self: *Self, entity: Entity, x: f32, y: f32, speed: f32) !void {
            const nearest = try self.findNearestNode(x, y);

            logInfo("Registering entity at ({d:.1}, {d:.1}), nearest node: {}", .{ x, y, nearest });

            const pos = PositionPF{
                .x = x,
                .y = y,
                .current_node = nearest,
                .edge_progress = 0,
                .target_node = null,
                .speed = speed,
                .path = .{},
                .path_index = 0,
            };

            try self.entities.put(entity, pos);
            _ = self.entity_spatial.insert(.{ .id = entity, .x = x, .y = y });
        }

        /// Unregister an entity
        pub fn unregisterEntity(self: *Self, entity: Entity) void {
            logInfo("Unregistering entity", .{});
            if (self.entities.getPtr(entity)) |pos| {
                pos.path.deinit(self.allocator);
            }
            _ = self.entities.remove(entity);
            _ = self.entity_spatial.remove(entity);
        }

        /// Set entity movement speed
        pub fn setSpeed(self: *Self, entity: Entity, speed: f32) void {
            if (self.entities.getPtr(entity)) |pos| {
                pos.speed = speed;
            }
        }

        /// Get entity movement speed
        pub fn getSpeed(self: *Self, entity: Entity) ?f32 {
            if (self.entities.get(entity)) |pos| {
                return pos.speed;
            }
            return null;
        }

        // =======================================================
        // Pathfinding Commands
        // =======================================================

        /// Request a path to a specific node
        pub fn requestPath(self: *Self, entity: Entity, target: NodeId) !void {
            const pos = self.entities.getPtr(entity) orelse {
                logWarn("Path request for unknown entity", .{});
                return error.EntityNotFound;
            };

            logInfo("Path requested from node {} to node {}", .{ pos.current_node, target });

            pos.path.clearRetainingCapacity();
            pos.path_index = 0;
            pos.target_node = target;

            if (pos.current_node == target) {
                logDebug("Entity already at target node {}", .{target});
                pos.target_node = null;
                return;
            }

            // Build path using Floyd-Warshall
            if (!self.floyd_warshall.hasPathWithMapping(pos.current_node, target)) {
                logWarn("No path exists from node {} to node {}", .{ pos.current_node, target });
                return error.NoPathExists;
            }

            var path_list: std.ArrayListUnmanaged(u32) = .{};
            defer path_list.deinit(self.allocator);
            try self.floyd_warshall.setPathWithMappingUnmanaged(self.allocator, &path_list, pos.current_node, target);

            // Convert to NodeId path (skip first node - current position)
            for (path_list.items[1..]) |node_id| {
                try pos.path.append(self.allocator, node_id);
            }

            logDebug("Path computed with {} nodes", .{pos.path.items.len});
        }

        /// Request a path to a position (snaps to nearest node)
        pub fn requestPathToPosition(self: *Self, entity: Entity, x: f32, y: f32) !void {
            const target = try self.findNearestNode(x, y);
            try self.requestPath(entity, target);
        }

        /// Cancel the current path
        pub fn cancelPath(self: *Self, entity: Entity) void {
            if (self.entities.getPtr(entity)) |pos| {
                pos.path.clearRetainingCapacity();
                pos.path_index = 0;
                pos.target_node = null;
            }
        }

        // =======================================================
        // Position Queries
        // =======================================================

        /// Get entity position (x, y only)
        pub fn getPosition(self: *Self, entity: Entity) ?struct { x: f32, y: f32 } {
            if (self.entities.get(entity)) |pos| {
                return .{ .x = pos.x, .y = pos.y };
            }
            return null;
        }

        /// Get full position data
        pub fn getPositionFull(self: *Self, entity: Entity) ?PositionPF {
            return self.entities.get(entity);
        }

        /// Check if entity is currently moving
        pub fn isMoving(self: *Self, entity: Entity) bool {
            if (self.entities.get(entity)) |pos| {
                return pos.target_node != null and pos.path_index < pos.path.items.len;
            }
            return false;
        }

        /// Get the current node of an entity
        pub fn getCurrentNode(self: *Self, entity: Entity) ?NodeId {
            if (self.entities.get(entity)) |pos| {
                return pos.current_node;
            }
            return null;
        }

        // =======================================================
        // Spatial Queries
        // =======================================================

        /// Get all entities within a radius
        pub fn getEntitiesInRadius(self: *Self, x: f32, y: f32, radius: f32, buffer: []Entity) []Entity {
            var result_buffer: std.ArrayListUnmanaged(EntityPoint(Entity)) = .{};
            defer result_buffer.deinit(self.allocator);

            self.entity_spatial.queryRadius(x, y, radius, &result_buffer) catch return buffer[0..0];

            const count = @min(buffer.len, result_buffer.items.len);
            for (result_buffer.items[0..count], 0..) |item, i| {
                buffer[i] = item.id;
            }
            return buffer[0..count];
        }

        /// Get all entities at a specific node
        pub fn getEntitiesAtNode(self: *Self, node: NodeId, buffer: []Entity) []Entity {
            const node_data = self.nodes.get(node) orelse return buffer[0..0];

            // Query a small radius around the node
            return self.getEntitiesInRadius(node_data.x, node_data.y, 5.0, buffer);
        }

        /// Get all entities within a rectangle
        pub fn getEntitiesInRect(self: *Self, x: f32, y: f32, w: f32, h: f32, buffer: []Entity) []Entity {
            var result_buffer: std.ArrayListUnmanaged(EntityPoint(Entity)) = .{};
            defer result_buffer.deinit(self.allocator);

            self.entity_spatial.queryRect(.{ .x = x, .y = y, .width = w, .height = h }, &result_buffer) catch return buffer[0..0];

            const count = @min(buffer.len, result_buffer.items.len);
            for (result_buffer.items[0..count], 0..) |item, i| {
                buffer[i] = item.id;
            }
            return buffer[0..count];
        }

        // =======================================================
        // Tick
        // =======================================================

        /// Update all entity positions and fire callbacks
        pub fn tick(self: *Self, ctx: Context, delta: f32) void {
            // Clear event buffers
            self.node_reached_events.clearRetainingCapacity();
            self.path_completed_events.clearRetainingCapacity();
            self.path_blocked_events.clearRetainingCapacity();

            // First pass: check waiting entities to see if they can now proceed
            self.processWaitingEntities();

            // Update all entities
            var iter = self.entities.iterator();
            while (iter.next()) |entry| {
                const entity = entry.key_ptr.*;
                const pos = entry.value_ptr;

                // Skip entities that are waiting for a stair
                if (pos.waiting_for_stair != null) {
                    continue;
                }

                if (pos.target_node == null or pos.path_index >= pos.path.items.len) {
                    continue;
                }

                const next_node_id = pos.path.items[pos.path_index];
                const next_node = self.nodes.get(next_node_id) orelse continue;

                // Check if next movement involves a stair
                const vertical_dir = self.getVerticalDirection(pos.current_node, next_node_id);
                if (vertical_dir) |dir| {
                    // This is vertical movement - check stair access
                    const stair_node = if (self.getStairMode(next_node_id) != .none)
                        next_node_id
                    else if (self.getStairMode(pos.current_node) != .none)
                        pos.current_node
                    else
                        null;

                    if (stair_node) |sn| {
                        if (self.stair_states.getPtr(sn)) |state| {
                            if (!state.canEnter(dir)) {
                                logDebug("Entity waiting for stair {} (direction: {})", .{ sn, @intFromEnum(dir) });
                                // Cannot enter stair - find waiting spot
                                if (self.findAvailableWaitingSpot(sn)) |wait_spot| {
                                    const wait_node = self.nodes.get(wait_spot) orelse continue;
                                    pos.waiting_for_stair = sn;
                                    pos.waiting_at_node = wait_spot;
                                    pos.waiting_direction = dir;
                                    // Mark spot as occupied
                                    if (self.waiting_areas.getPtr(sn)) |area| {
                                        area.occupySpot(wait_spot, entity);
                                    }
                                    // Move to waiting spot
                                    pos.x = wait_node.x;
                                    pos.y = wait_node.y;
                                    _ = self.entity_spatial.update(entity, pos.x, pos.y);
                                }
                                // Add to waiting queue
                                state.waiting_queue.append(self.allocator, entity) catch |err| {
                                    logErr("Failed to add entity to stair waiting queue: {}", .{err});
                                    // Clear waiting state since we couldn't add to queue
                                    if (pos.waiting_at_node) |spot| {
                                        if (self.waiting_areas.getPtr(sn)) |area| {
                                            area.releaseSpot(spot);
                                        }
                                    }
                                    pos.waiting_for_stair = null;
                                    pos.waiting_at_node = null;
                                    pos.waiting_direction = null;
                                };
                                continue;
                            } else {
                                // Can enter - register as user
                                logDebug("Entity entering stair {} (direction: {})", .{ sn, @intFromEnum(dir) });
                                state.enter(dir);
                                pos.using_stair = sn;
                            }
                        }
                    }
                }

                // Calculate direction and distance
                const dx = next_node.x - pos.x;
                const dy = next_node.y - pos.y;
                const dist = @sqrt(dx * dx + dy * dy);

                if (dist < 1.0) {
                    // Reached node - check if we need to exit a stair
                    if (pos.using_stair) |stair_node| {
                        // Check if we're leaving the stair (current node is different from stair node)
                        if (next_node_id != stair_node) {
                            logDebug("Entity exiting stair {}", .{stair_node});
                            if (self.stair_states.getPtr(stair_node)) |state| {
                                state.exit();
                            }
                            pos.using_stair = null;
                        }
                    }

                    logDebug("Entity reached node {} (path step {}/{})", .{ next_node_id, pos.path_index + 1, pos.path.items.len });

                    pos.x = next_node.x;
                    pos.y = next_node.y;
                    pos.current_node = next_node_id;
                    pos.path_index += 1;
                    pos.edge_progress = 0;

                    // Queue node reached event
                    self.node_reached_events.append(self.allocator, .{ .entity = entity, .node = next_node_id }) catch |err| {
                        logErr("Failed to queue node_reached event: {}", .{err});
                    };

                    // Check if path complete
                    if (pos.path_index >= pos.path.items.len) {
                        logDebug("Entity completed path at node {}", .{next_node_id});
                        pos.target_node = null;
                        // Make sure to exit stair if we finished on one
                        if (pos.using_stair) |stair_node| {
                            if (self.stair_states.getPtr(stair_node)) |state| {
                                state.exit();
                            }
                            pos.using_stair = null;
                        }
                        self.path_completed_events.append(self.allocator, .{ .entity = entity, .node = next_node_id }) catch |err| {
                            logErr("Failed to queue path_completed event: {}", .{err});
                        };
                    }
                } else {
                    // Move towards node
                    const move_dist = pos.speed * delta;
                    const ratio = @min(1.0, move_dist / dist);
                    pos.x += dx * ratio;
                    pos.y += dy * ratio;

                    // Update spatial index
                    _ = self.entity_spatial.update(entity, pos.x, pos.y);
                }
            }

            // Fire callbacks after iteration
            if (self.on_node_reached) |cb| {
                for (self.node_reached_events.items) |event| {
                    cb(ctx, event.entity, event.node);
                }
            }

            if (self.on_path_completed) |cb| {
                for (self.path_completed_events.items) |event| {
                    cb(ctx, event.entity, event.node);
                }
            }

            if (self.on_path_blocked) |cb| {
                for (self.path_blocked_events.items) |event| {
                    cb(ctx, event.entity, event.node);
                }
            }
        }

        /// Process entities waiting for stairs
        fn processWaitingEntities(self: *Self) void {
            var iter = self.entities.iterator();
            while (iter.next()) |entry| {
                const entity = entry.key_ptr.*;
                const pos = entry.value_ptr;

                const stair_node = pos.waiting_for_stair orelse continue;
                const dir = pos.waiting_direction orelse continue;

                if (self.stair_states.getPtr(stair_node)) |state| {
                    if (state.canEnter(dir)) {
                        // Can now enter - remove from waiting
                        logDebug("Entity proceeding from stair {} queue (direction: {})", .{ stair_node, @intFromEnum(dir) });
                        state.enter(dir);
                        pos.using_stair = stair_node;

                        // Release the waiting spot
                        if (pos.waiting_at_node) |wait_spot| {
                            if (self.waiting_areas.getPtr(stair_node)) |area| {
                                area.releaseSpot(wait_spot);
                            }
                        }

                        pos.waiting_for_stair = null;
                        pos.waiting_at_node = null;
                        pos.waiting_direction = null;

                        // Remove from waiting queue
                        if (std.mem.indexOfScalar(Entity, state.waiting_queue.items, entity)) |idx| {
                            _ = state.waiting_queue.swapRemove(idx);
                        }

                        // Move back to the node before the stair
                        const current = self.nodes.get(pos.current_node) orelse continue;
                        pos.x = current.x;
                        pos.y = current.y;
                        _ = self.entity_spatial.update(entity, pos.x, pos.y);
                    }
                }
            }
        }

        // =======================================================
        // Helpers
        // =======================================================

        fn findNearestNode(self: *Self, x: f32, y: f32) !NodeId {
            var buffer: std.ArrayListUnmanaged(EntityPoint(NodeId)) = .{};
            defer buffer.deinit(self.allocator);

            // Start with a small radius and expand
            var radius: f32 = 50.0;
            while (radius < 10000.0) {
                buffer.clearRetainingCapacity();
                try self.node_spatial.queryRadius(x, y, radius, &buffer);

                if (buffer.items.len > 0) {
                    // Find closest
                    var closest: ?NodeId = null;
                    var closest_dist: f32 = std.math.inf(f32);

                    for (buffer.items) |node| {
                        const ndx = node.x - x;
                        const ndy = node.y - y;
                        const ndist = ndx * ndx + ndy * ndy;
                        if (ndist < closest_dist) {
                            closest_dist = ndist;
                            closest = node.id;
                        }
                    }

                    if (closest) |id| return id;
                }

                radius *= 2;
            }

            return error.NoNodesFound;
        }

        /// Get node position
        pub fn getNodePosition(self: *Self, node: NodeId) ?struct { x: f32, y: f32 } {
            if (self.nodes.get(node)) |data| {
                return .{ .x = data.x, .y = data.y };
            }
            return null;
        }

        /// Get directional edges for a node (only valid after connectNodes with directional mode)
        pub fn getDirectionalEdges(self: *Self, node: NodeId) ?DirectionalEdges {
            return self.directional_edges.get(node);
        }

        /// Get all edges from a node
        pub fn getEdges(self: *Self, node: NodeId) ?[]const NodeId {
            if (self.edges.get(node)) |edge_list| {
                return edge_list.items;
            }
            return null;
        }

        /// Get total node count
        pub fn getNodeCount(self: *Self) usize {
            return self.nodes.count();
        }

        /// Get total entity count
        pub fn getEntityCount(self: *Self) usize {
            return self.entities.count();
        }

        // =======================================================
        // Stair Management
        // =======================================================

        /// Get stair state for a node
        pub fn getStairState(self: *Self, node: NodeId) ?*StairState {
            return self.stair_states.getPtr(node);
        }

        /// Get stair mode for a node
        pub fn getStairMode(self: *Self, node: NodeId) StairMode {
            if (self.nodes.get(node)) |data| {
                return data.stair_mode;
            }
            return .none;
        }

        /// Set waiting area spots for a stair node
        pub fn setWaitingArea(self: *Self, stair_node: NodeId, spots: []const NodeId) !void {
            // Clean up existing if present
            if (self.waiting_areas.fetchRemove(stair_node)) |removed| {
                var existing = removed.value;
                existing.deinit(self.allocator);
            }
            var area = WaitingArea.init(self.allocator, stair_node);
            for (spots) |spot| {
                try area.waiting_spots.append(self.allocator, spot);
            }
            try self.waiting_areas.put(stair_node, area);
        }

        /// Get waiting area for a stair node
        pub fn getWaitingArea(self: *Self, node: NodeId) ?*WaitingArea {
            return self.waiting_areas.getPtr(node);
        }

        /// Check if an entity can enter a stair
        pub fn canEnterStair(self: *Self, stair_node: NodeId, direction: VerticalDirection) bool {
            if (self.stair_states.getPtr(stair_node)) |state| {
                return state.canEnter(direction);
            }
            // If no stair state, it's not a stair
            return false;
        }

        /// Find an available waiting spot around a stair (O(spots) instead of O(entities))
        fn findAvailableWaitingSpot(self: *Self, stair_node: NodeId) ?NodeId {
            const area = self.waiting_areas.getPtr(stair_node) orelse return null;
            return area.findAvailableSpot();
        }

        /// Determine vertical direction between two nodes
        fn getVerticalDirection(self: *Self, from_node: NodeId, to_node: NodeId) ?VerticalDirection {
            const from = self.nodes.get(from_node) orelse return null;
            const to = self.nodes.get(to_node) orelse return null;

            if (to.y < from.y) return .up;
            if (to.y > from.y) return .down;
            return null;
        }

        /// Check if movement between two nodes involves a stair
        fn isStairMovement(self: *Self, from_node: NodeId, to_node: NodeId) bool {
            const dir = self.getVerticalDirection(from_node, to_node) orelse return false;
            _ = dir;
            // Check if either node is a stair
            const from_mode = self.getStairMode(from_node);
            const to_mode = self.getStairMode(to_node);
            return from_mode != .none or to_mode != .none;
        }
    };
}

test "PathfindingEngine basic" {
    const TestConfig = struct {
        pub const Entity = u32;
        pub const Context = *anyopaque;
    };

    const Engine = PathfindingEngine(TestConfig);
    var engine = try Engine.init(std.testing.allocator);
    defer engine.deinit();

    // Add nodes
    try engine.addNode(0, 0, 0);
    try engine.addNode(1, 100, 0);
    try engine.addNode(2, 200, 0);

    try std.testing.expectEqual(@as(usize, 3), engine.getNodeCount());

    // Connect nodes
    try engine.connectNodes(.{ .omnidirectional = .{ .max_distance = 150, .max_connections = 4 } });
    try engine.rebuildPaths();

    // Register entity
    try engine.registerEntity(1, 0, 0, 100);
    try std.testing.expectEqual(@as(usize, 1), engine.getEntityCount());

    // Check position
    const pos = engine.getPosition(1);
    try std.testing.expect(pos != null);
    try std.testing.expectEqual(@as(f32, 0), pos.?.x);

    // Request path
    try engine.requestPath(1, 2);
    try std.testing.expect(engine.isMoving(1));

    // Tick
    var dummy: u32 = 0;
    engine.tick(&dummy, 0.5);

    // Position should have moved
    const new_pos = engine.getPosition(1);
    try std.testing.expect(new_pos.?.x > 0);
}
