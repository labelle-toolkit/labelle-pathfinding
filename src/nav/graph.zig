const std = @import("std");
const types = @import("types.zig");

const NodeId = types.NodeId;
const Position = types.Position;
const distanceBetween = types.distanceBetween;
const Allocator = std.mem.Allocator;

pub const Config = struct {
    /// Cap on edge length for **vertical** connections (same-X axis,
    /// different Y) — the climb between two stair nodes on adjacent
    /// floors. Was `max_connection_distance`; renamed for clarity now
    /// that the horizontal counterpart got a non-misleading name too.
    max_vertical_distance: f32,
    /// Cap on edge length for **horizontal** connections (same-Y
    /// axis, different X) — i.e. corridor walking on a single floor.
    /// Was `max_stair_distance`; the old name dated from when only
    /// stair nodes participated in this axis (the RFC still describes
    /// that older shape), but the implementation has long since
    /// applied this cap to *all* MovementNodes regardless of whether
    /// they're stairs.
    max_horizontal_distance: f32,
    axis_tolerance: f32 = 1.0,
};

pub const Edge = struct {
    to: NodeId,
    cost: f32,
};

const EdgeList = std.ArrayListUnmanaged(Edge);

pub const Graph = struct {
    allocator: Allocator,
    /// Node positions indexed by NodeId.
    positions: std.ArrayListUnmanaged(Position) = .empty,
    /// Whether each node is a stair node.
    is_stair: std.ArrayListUnmanaged(bool) = .empty,
    /// Whether each node has been removed (tombstone).
    removed: std.ArrayListUnmanaged(bool) = .empty,
    /// Adjacency list: edges[node_id] = list of { neighbor_id, cost }.
    edges: std.ArrayListUnmanaged(EdgeList) = .empty,
    /// Config loaded from pathfinder.zon.
    config: Config,
    /// Dirty flag — set on any mutation, cleared after Floyd-Warshall rebuild.
    dirty: bool = true,

    pub fn init(allocator: Allocator, config: Config) Graph {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn deinit(self: *Graph) void {
        for (self.edges.items) |*edge_list| {
            edge_list.deinit(self.allocator);
        }
        self.edges.deinit(self.allocator);
        self.positions.deinit(self.allocator);
        self.is_stair.deinit(self.allocator);
        self.removed.deinit(self.allocator);
    }

    /// Register a new node. Returns its NodeId.
    ///
    /// Auto-connects to existing nodes on:
    /// * The same X axis (vertical) within `max_vertical_distance` —
    ///   to its nearest neighbour above and below, where the UPPER node
    ///   of the pair is a stair (`autoConnectVertical`).
    /// * The same Y axis (horizontal) within `max_horizontal_distance` —
    ///   applies to every MovementNode, regardless of `is_stair`.
    ///
    /// Sets dirty = true.
    pub fn addNode(self: *Graph, position: Position, stair: bool) !NodeId {
        const new_id: NodeId = @intCast(self.positions.items.len);

        try self.positions.append(self.allocator, position);
        try self.is_stair.append(self.allocator, stair);
        try self.removed.append(self.allocator, false);
        try self.edges.append(self.allocator, .empty);

        // Auto-connect on same X axis (vertical, between floors: a stair
        // reaching down)
        try self.autoConnectVertical(new_id, position, stair);

        // Auto-connect on same Y axis (horizontal, same level) for all nodes
        try self.autoConnectHorizontal(new_id, position);

        self.dirty = true;
        return new_id;
    }

    /// Vertical links (same X, different Y): a stair reaches DOWN to the
    /// nearest node under it, whatever that node is; nothing reaches up
    /// to a node that is not a stair. So a link joins the new node to its
    /// nearest neighbour above when that neighbour is a stair, and to its
    /// nearest neighbour below when the new node is one.
    ///
    /// "Nearest" counts every node on the X, stair or not: a node between
    /// two others stands in the way of a link between them, also when it
    /// links to neither. That makes the result the same in whatever order
    /// the nodes are added. Before, a plain node was only ever compared
    /// with stairs, so one added under a floor linked to a stair two
    /// floors up, straight through that floor (#69).
    fn autoConnectVertical(self: *Graph, new_id: NodeId, position: Position, is_new_stair: bool) !void {
        const max_dist = self.config.max_vertical_distance;
        var above: ?NodeId = null;
        var above_dist: f32 = max_dist + 1.0;
        var below: ?NodeId = null;
        var below_dist: f32 = max_dist + 1.0;

        for (self.positions.items, 0..) |other_pos, i| {
            const other_id: NodeId = @intCast(i);
            if (other_id == new_id) continue;
            if (self.removed.items[i]) continue;
            if (@abs(other_pos.x - position.x) > self.config.axis_tolerance) continue;
            const dist = distanceBetween(position, other_pos);
            if (dist > max_dist) continue;

            // A node at the very same height is neither above nor below:
            // there is no floor between the two, so it blocks nothing and
            // takes no vertical link. The horizontal pass joins the pair
            // (it counts a node on the same X as a neighbour).
            if (other_pos.y == position.y) continue;
            if (other_pos.y < position.y) {
                if (dist < below_dist) {
                    below = other_id;
                    below_dist = dist;
                }
            } else if (dist < above_dist or (dist == above_dist and self.is_stair.items[i])) {
                // Of two nodes on one spot, the stair is the neighbour:
                // it is the one that can take the link.
                above = other_id;
                above_dist = dist;
            }
        }

        if (above) |a| {
            if (self.is_stair.items[a]) try self.addBidirectionalEdge(new_id, a, above_dist);
        }
        if (below) |b| {
            if (is_new_stair) try self.addBidirectionalEdge(new_id, b, below_dist);
        }
        // The new node stands between its two neighbours: a link they had
        // goes, whether or not the new node takes its place. Last, so an
        // allocation failure above leaves that link standing.
        if (above) |a| if (below) |b| self.removeEdgeBetween(a, b);
    }

    /// Horizontal links (same Y, different X): the nearest node to the
    /// left and to the right within `max_horizontal_distance`, stair or
    /// not. A link the two had goes: the new node is in between.
    fn autoConnectHorizontal(self: *Graph, new_id: NodeId, position: Position) !void {
        const max_dist = self.config.max_horizontal_distance;
        var right: ?NodeId = null;
        var right_dist: f32 = max_dist + 1.0;
        var left: ?NodeId = null;
        var left_dist: f32 = max_dist + 1.0;

        for (self.positions.items, 0..) |other_pos, i| {
            const other_id: NodeId = @intCast(i);
            if (other_id == new_id) continue;
            if (self.removed.items[i]) continue;
            if (@abs(other_pos.y - position.y) > self.config.axis_tolerance) continue;
            const dist = distanceBetween(position, other_pos);
            if (dist > max_dist) continue;

            // A node at the very same X counts as to the right.
            if (other_pos.x < position.x) {
                if (dist < left_dist) {
                    left = other_id;
                    left_dist = dist;
                }
            } else if (dist < right_dist) {
                right = other_id;
                right_dist = dist;
            }
        }

        if (right) |r| {
            try self.addBidirectionalEdge(new_id, r, right_dist);
            if (left) |l| self.removeEdgeBetween(r, l);
        }
        if (left) |l| try self.addBidirectionalEdge(new_id, l, left_dist);
    }

    /// Link two nodes directly, whatever their axes and distance: the
    /// authored connections the axis auto-connect can't express, such as
    /// a diagonal flight of steps. The cost is the straight-line distance,
    /// and the walker walks it as one straight leg. No-op when the nodes
    /// are already linked; error on a removed or unknown node.
    ///
    /// A diagonal link survives later `addNode` calls: the in-between
    /// pruning only drops edges between two nodes on the new node's axis.
    /// An axis-aligned link can be pruned that way, like any other edge.
    /// Sets dirty = true.
    pub fn addLink(self: *Graph, a: NodeId, b: NodeId) !void {
        if (a == b or self.isRemoved(a) or self.isRemoved(b)) return error.InvalidNode;
        for (self.edges.items[a].items) |edge| {
            if (edge.to == b) return;
        }
        try self.addBidirectionalEdge(a, b, distanceBetween(self.positions.items[a], self.positions.items[b]));
        self.dirty = true;
    }

    /// The active node nearest `position`, if one is within `tolerance`.
    pub fn nearestNodeWithin(self: *const Graph, position: Position, tolerance: f32) ?NodeId {
        var best: ?NodeId = null;
        var best_dist = tolerance;
        for (self.positions.items, 0..) |p, i| {
            if (self.removed.items[i]) continue;
            const dist = distanceBetween(position, p);
            if (dist <= best_dist) {
                best = @intCast(i);
                best_dist = dist;
            }
        }
        return best;
    }

    fn addBidirectionalEdge(self: *Graph, a: NodeId, b: NodeId, cost: f32) !void {
        try self.edges.items[a].append(self.allocator, .{ .to = b, .cost = cost });
        // If the second append OOMs, roll back the first so the graph is never
        // left half-connected (a→b without b→a). `pop` drops exactly the edge we
        // just appended.
        errdefer {
            _ = self.edges.items[a].pop();
        }
        try self.edges.items[b].append(self.allocator, .{ .to = a, .cost = cost });
    }

    fn removeEdgeBetween(self: *Graph, a: NodeId, b: NodeId) void {
        removeEdgeFromList(&self.edges.items[a], b);
        removeEdgeFromList(&self.edges.items[b], a);
    }

    fn removeEdgeFromList(edge_list: *EdgeList, target: NodeId) void {
        var i: usize = 0;
        while (i < edge_list.items.len) {
            if (edge_list.items[i].to == target) {
                _ = edge_list.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Remove a node and all its edges. Sets dirty = true.
    pub fn removeNode(self: *Graph, node_id: NodeId) void {
        if (node_id >= self.positions.items.len) return;
        if (self.removed.items[node_id]) return;

        // Remove all edges from this node
        for (self.edges.items[node_id].items) |edge| {
            removeEdgeFromList(&self.edges.items[edge.to], node_id);
        }
        self.edges.items[node_id].clearRetainingCapacity();

        // Mark as removed (tombstone)
        self.removed.items[node_id] = true;
        self.dirty = true;
    }

    /// Number of active (non-removed) nodes.
    pub fn nodeCount(self: *const Graph) u32 {
        var count: u32 = 0;
        for (self.removed.items) |r| {
            if (!r) count += 1;
        }
        return count;
    }

    /// Total number of node slots (including removed).
    pub fn totalSlots(self: *const Graph) u32 {
        return @intCast(self.positions.items.len);
    }

    /// Get the world position of a node.
    pub fn getPosition(self: *const Graph, node_id: NodeId) Position {
        return self.positions.items[node_id];
    }

    /// Get edges for a node.
    pub fn getEdges(self: *const Graph, node_id: NodeId) []const Edge {
        return self.edges.items[node_id].items;
    }

    /// Check if a node has been removed.
    pub fn isRemoved(self: *const Graph, node_id: NodeId) bool {
        if (node_id >= self.removed.items.len) return true;
        return self.removed.items[node_id];
    }
};
