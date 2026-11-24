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
    ///
    /// Nodes on one spot (same X and Y) have no floor between them: they
    /// are joined by the horizontal pass, and the stair among them holds
    /// the spot's vertical links.
    fn autoConnectVertical(self: *Graph, new_id: NodeId, position: Position, is_new_stair: bool) !void {
        const max_dist = self.config.max_vertical_distance;
        var above: ?NodeId = null;
        var above_dist: f32 = max_dist + 1.0;
        var below: ?NodeId = null;
        var below_dist: f32 = max_dist + 1.0;
        var stair_on_spot = false;

        for (self.positions.items, 0..) |other_pos, i| {
            const other_id: NodeId = @intCast(i);
            if (other_id == new_id or !self.inColumn(other_id, position.x)) continue;
            if (other_pos.y == position.y) {
                // The very same spot, not merely the same column: a stair
                // a pixel to the side has neighbours of its own.
                if (self.is_stair.items[i] and other_pos.x == position.x) stair_on_spot = true;
                continue;
            }
            const dist = distanceBetween(position, other_pos);
            if (dist > max_dist) continue;

            // Of two nodes on one spot, the stair is the neighbour.
            const stair = self.is_stair.items[i];
            if (other_pos.y < position.y) {
                if (dist < below_dist or (dist == below_dist and stair)) {
                    below = other_id;
                    below_dist = dist;
                }
            } else if (dist < above_dist or (dist == above_dist and stair)) {
                above = other_id;
                above_dist = dist;
            }
        }

        // A plain node on a stair's spot: the stair already holds the
        // spot's vertical links, and the node is between nothing new.
        if (!is_new_stair and stair_on_spot) return;

        if (above) |a| {
            if (self.is_stair.items[a]) try self.addBidirectionalEdge(new_id, a, above_dist);
        }
        if (below) |b| {
            if (is_new_stair) try self.addBidirectionalEdge(new_id, b, below_dist);
        }

        // After the links are added, so an allocation failure above leaves
        // the old ones standing.
        for (self.positions.items, 0..) |other_pos, i| {
            const other_id: NodeId = @intCast(i);
            if (other_id == new_id or !self.inColumn(other_id, position.x)) continue;
            if (other_pos.y > position.y) {
                // The new node stands between this node and everything
                // under the new node: a link across it goes.
                self.removeColumnEdges(other_id, position.x, .below, position.y);
            } else if (other_pos.y == position.y and other_pos.x == position.x and is_new_stair and !self.is_stair.items[i]) {
                // A stair arriving on a plain node's spot takes over the
                // vertical links that node had.
                self.removeColumnEdges(other_id, position.x, .off, position.y);
            }
        }
    }

    /// An active node on the X axis `x` (within `axis_tolerance`).
    fn inColumn(self: *const Graph, node_id: NodeId, x: f32) bool {
        return !self.removed.items[node_id] and @abs(self.positions.items[node_id].x - x) <= self.config.axis_tolerance;
    }

    /// Drop `node_id`'s vertical links to the nodes of column `x` that are
    /// `.below` the height `y`, or `.off` it (above or below). Vertical:
    /// the two ends share an X themselves. Two nodes on either edge of the
    /// column's tolerance are a diagonal, an authored link (`addLink`)
    /// that stays.
    fn removeColumnEdges(self: *Graph, node_id: NodeId, x: f32, which: enum { below, off }, y: f32) void {
        const from_x = self.positions.items[node_id].x;
        var i: usize = 0;
        while (i < self.edges.items[node_id].items.len) {
            const to = self.edges.items[node_id].items[i].to;
            const to_y = self.positions.items[to].y;
            const vertical = @abs(self.positions.items[to].x - from_x) <= self.config.axis_tolerance;
            const hit = vertical and self.inColumn(to, x) and switch (which) {
                .below => to_y < y,
                .off => to_y != y,
            };
            if (hit) {
                // Swap-removes from both lists: look at index `i` again.
                self.removeEdgeBetween(node_id, to);
            } else {
                i += 1;
            }
        }
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
