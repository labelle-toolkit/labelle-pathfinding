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

/// Node identifier type
pub const NodeId = u32;

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
};

/// Node data stored in the graph
pub const NodeData = struct {
    x: f32,
    y: f32,
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

    return struct {
        const Self = @This();

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
        };

        /// Directional edges for platformer-style connections
        pub const DirectionalEdges = struct {
            left: ?NodeId = null,
            right: ?NodeId = null,
            up: ?NodeId = null,
            down: ?NodeId = null,
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

        // === Callbacks ===
        on_node_reached: ?*const fn (Context, Entity, NodeId) void = null,
        on_path_completed: ?*const fn (Context, Entity, NodeId) void = null,
        on_path_blocked: ?*const fn (Context, Entity, NodeId) void = null,

        // Event buffers for deferred callbacks
        node_reached_events: std.ArrayListUnmanaged(PathEvent),
        path_completed_events: std.ArrayListUnmanaged(PathEvent),
        path_blocked_events: std.ArrayListUnmanaged(PathEvent),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .nodes = std.AutoHashMap(NodeId, NodeData).init(allocator),
                .edges = std.AutoHashMap(NodeId, std.ArrayListUnmanaged(NodeId)).init(allocator),
                .directional_edges = std.AutoHashMap(NodeId, DirectionalEdges).init(allocator),
                .node_spatial = QuadTree(NodeId).init(allocator, .{ .x = -50000, .y = -50000, .width = 100000, .height = 100000 }),
                .floyd_warshall = FloydWarshall.init(allocator),
                .entities = std.AutoHashMap(Entity, PositionPF).init(allocator),
                .entity_spatial = QuadTree(Entity).init(allocator, .{ .x = -50000, .y = -50000, .width = 100000, .height = 100000 }),
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

        /// Add a node at the given position
        pub fn addNode(self: *Self, id: NodeId, x: f32, y: f32) !void {
            try self.nodes.put(id, .{ .x = x, .y = y });
            _ = self.node_spatial.insert(.{ .id = id, .x = x, .y = y });
            if (id >= self.next_node_id) {
                self.next_node_id = id + 1;
            }
        }

        /// Add a node and return the auto-generated ID
        pub fn addNodeAuto(self: *Self, x: f32, y: f32) !NodeId {
            const id = self.next_node_id;
            try self.addNode(id, x, y);
            return id;
        }

        /// Remove a node from the graph
        pub fn removeNode(self: *Self, id: NodeId) void {
            _ = self.nodes.remove(id);
            if (self.edges.getPtr(id)) |edge_list| {
                edge_list.deinit(self.allocator);
            }
            _ = self.edges.remove(id);
            _ = self.directional_edges.remove(id);
            _ = self.node_spatial.remove(id);
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

            self.node_spatial.resetWithBoundaries(points.items);

            node_iter = self.nodes.iterator();
            while (node_iter.next()) |entry| {
                _ = self.node_spatial.insert(.{ .id = entry.key_ptr.*, .x = entry.value_ptr.x, .y = entry.value_ptr.y });
            }

            // Connect based on mode
            switch (mode) {
                .omnidirectional => |config| try self.connectOmnidirectional(config.max_distance, config.max_connections),
                .directional => |config| try self.connectDirectional(config.horizontal_range, config.vertical_range),
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
                    const dist: u64 = @intFromFloat(@sqrt(dx * dx + dy * dy));
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
            const pos = self.entities.getPtr(entity) orelse return error.EntityNotFound;

            pos.path.clearRetainingCapacity();
            pos.path_index = 0;
            pos.target_node = target;

            if (pos.current_node == target) {
                pos.target_node = null;
                return;
            }

            // Build path using Floyd-Warshall
            if (!self.floyd_warshall.hasPathWithMapping(pos.current_node, target)) {
                return error.NoPathExists;
            }

            var path_list: std.ArrayListUnmanaged(u32) = .{};
            defer path_list.deinit(self.allocator);
            try self.floyd_warshall.setPathWithMappingUnmanaged(self.allocator, &path_list, pos.current_node, target);

            // Convert to NodeId path (skip first node - current position)
            for (path_list.items[1..]) |node_id| {
                try pos.path.append(self.allocator, node_id);
            }
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

            // Update all entities
            var iter = self.entities.iterator();
            while (iter.next()) |entry| {
                const entity = entry.key_ptr.*;
                const pos = entry.value_ptr;

                if (pos.target_node == null or pos.path_index >= pos.path.items.len) {
                    continue;
                }

                const next_node_id = pos.path.items[pos.path_index];
                const next_node = self.nodes.get(next_node_id) orelse continue;

                // Calculate direction and distance
                const dx = next_node.x - pos.x;
                const dy = next_node.y - pos.y;
                const dist = @sqrt(dx * dx + dy * dy);

                if (dist < 1.0) {
                    // Reached node
                    pos.x = next_node.x;
                    pos.y = next_node.y;
                    pos.current_node = next_node_id;
                    pos.path_index += 1;
                    pos.edge_progress = 0;

                    // Queue node reached event
                    self.node_reached_events.append(self.allocator, .{ .entity = entity, .node = next_node_id }) catch {};

                    // Check if path complete
                    if (pos.path_index >= pos.path.items.len) {
                        pos.target_node = null;
                        self.path_completed_events.append(self.allocator, .{ .entity = entity, .node = next_node_id }) catch {};
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
    };
}

test "PathfindingEngine basic" {
    const TestConfig = struct {
        pub const Entity = u32;
        pub const Context = *anyopaque;
    };

    const Engine = PathfindingEngine(TestConfig);
    var engine = Engine.init(std.testing.allocator);
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
