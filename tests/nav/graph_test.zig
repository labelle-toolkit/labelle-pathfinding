const std = @import("std");
const pathfinder = @import("pathfinder");

const Graph = pathfinder.Graph;
const Config = pathfinder.Config;

const test_config = Config{
    .max_vertical_distance = 200.0,
    .max_horizontal_distance = 150.0,
    .axis_tolerance = 1.0,
};

// --- Initialization ---

test "starts with zero nodes" {
    var g = Graph.init(std.testing.allocator, test_config);
    defer g.deinit();

    try std.testing.expectEqual(@as(u32, 0), g.nodeCount());
}

test "starts dirty" {
    var g = Graph.init(std.testing.allocator, test_config);
    defer g.deinit();

    try std.testing.expect(g.dirty);
}

// --- addNode ---

test "addNode returns incrementing NodeIds" {
    var g = Graph.init(std.testing.allocator, test_config);
    defer g.deinit();

    const id0 = try g.addNode(.{ .x = 100, .y = 100 }, false);
    const id1 = try g.addNode(.{ .x = 200, .y = 200 }, false);
    const id2 = try g.addNode(.{ .x = 300, .y = 300 }, false);

    try std.testing.expectEqual(@as(u32, 0), id0);
    try std.testing.expectEqual(@as(u32, 1), id1);
    try std.testing.expectEqual(@as(u32, 2), id2);
    try std.testing.expectEqual(@as(u32, 3), g.nodeCount());
}

test "nodes on same X axis connect automatically" {
    var g = Graph.init(std.testing.allocator, test_config);
    defer g.deinit();

    // X-axis (vertical, between floors) requires at least one stair.
    // Two nodes on same X=100, Y differs by 100 (within max_vertical_distance=200).
    const a = try g.addNode(.{ .x = 100, .y = 100 }, true);
    const b = try g.addNode(.{ .x = 100, .y = 200 }, true);

    // a should have edge to b
    const a_edges = g.getEdges(a);
    try std.testing.expectEqual(@as(usize, 1), a_edges.len);
    try std.testing.expectEqual(b, a_edges[0].to);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), a_edges[0].cost, 0.01);

    // b should have edge to a
    const b_edges = g.getEdges(b);
    try std.testing.expectEqual(@as(usize, 1), b_edges.len);
    try std.testing.expectEqual(a, b_edges[0].to);
}

test "nodes on different X and different Y do not connect" {
    var g = Graph.init(std.testing.allocator, test_config);
    defer g.deinit();

    // Different X and different Y — no shared axis, no auto-connection.
    const a = try g.addNode(.{ .x = 100, .y = 100 }, true);
    _ = try g.addNode(.{ .x = 250, .y = 500 }, true);

    try std.testing.expectEqual(@as(usize, 0), g.getEdges(a).len);
}

test "nearest neighbor only — no skip connections" {
    var g = Graph.init(std.testing.allocator, test_config);
    defer g.deinit();

    // Three stair nodes on same X=100: A at y=100, B at y=200, C at y=300.
    // X-axis (vertical) requires a stair on at least one of the two nodes —
    // marking all three as stairs keeps the chain fully connected.
    const a = try g.addNode(.{ .x = 100, .y = 100 }, true);
    const b = try g.addNode(.{ .x = 100, .y = 200 }, true);
    const c = try g.addNode(.{ .x = 100, .y = 300 }, true);

    // A connects to B (nearest above)
    const a_edges = g.getEdges(a);
    try std.testing.expectEqual(@as(usize, 1), a_edges.len);
    try std.testing.expectEqual(b, a_edges[0].to);

    // B connects to A (below) and C (above)
    const b_edges = g.getEdges(b);
    try std.testing.expectEqual(@as(usize, 2), b_edges.len);

    // C connects to B only (nearest below), NOT to A
    const c_edges = g.getEdges(c);
    try std.testing.expectEqual(@as(usize, 1), c_edges.len);
    try std.testing.expectEqual(b, c_edges[0].to);
}

test "does not connect beyond max_vertical_distance" {
    var g = Graph.init(std.testing.allocator, test_config);
    defer g.deinit();

    // Two stair nodes on same X but 250 apart (exceeds max_vertical_distance=200).
    // Use stairs so the X-axis filter (requires a stair) is not the reason for disconnect.
    const a = try g.addNode(.{ .x = 100, .y = 100 }, true);
    _ = try g.addNode(.{ .x = 100, .y = 350 }, true);

    try std.testing.expectEqual(@as(usize, 0), g.getEdges(a).len);
}

test "axis_tolerance allows near-matches" {
    var g = Graph.init(std.testing.allocator, test_config);
    defer g.deinit();

    // Stair nodes at x=100 and x=100.5 (within tolerance=1.0).
    // X-axis auto-connect requires at least one stair; flag both to exercise tolerance.
    const a = try g.addNode(.{ .x = 100.0, .y = 100 }, true);
    const b = try g.addNode(.{ .x = 100.5, .y = 200 }, true);

    const a_edges = g.getEdges(a);
    try std.testing.expectEqual(@as(usize, 1), a_edges.len);
    try std.testing.expectEqual(b, a_edges[0].to);
}

test "sets dirty flag on addNode" {
    var g = Graph.init(std.testing.allocator, test_config);
    defer g.deinit();

    g.dirty = false;
    _ = try g.addNode(.{ .x = 100, .y = 100 }, false);
    try std.testing.expect(g.dirty);
}

test "edge re-evaluation when inserting between connected nodes" {
    var g = Graph.init(std.testing.allocator, test_config);
    defer g.deinit();

    // All stairs so the X-axis chain auto-connects under new semantics.
    // A at y=100, B at y=200 — they connect.
    const a = try g.addNode(.{ .x = 100, .y = 100 }, true);
    const b = try g.addNode(.{ .x = 100, .y = 200 }, true);

    // Verify A-B connected
    try std.testing.expectEqual(@as(usize, 1), g.getEdges(a).len);
    try std.testing.expectEqual(@as(usize, 1), g.getEdges(b).len);

    // Insert C at y=150 (between A and B)
    const c = try g.addNode(.{ .x = 100, .y = 150 }, true);

    // Now A should connect to C (nearest above), NOT B
    const a_edges = g.getEdges(a);
    try std.testing.expectEqual(@as(usize, 1), a_edges.len);
    try std.testing.expectEqual(c, a_edges[0].to);

    // C should connect to both A (below) and B (above)
    const c_edges = g.getEdges(c);
    try std.testing.expectEqual(@as(usize, 2), c_edges.len);

    // B should connect to C only, NOT A
    const b_edges = g.getEdges(b);
    try std.testing.expectEqual(@as(usize, 1), b_edges.len);
    try std.testing.expectEqual(c, b_edges[0].to);
}

// --- Stairs ---

test "stair nodes on same Y axis connect" {
    var g = Graph.init(std.testing.allocator, test_config);
    defer g.deinit();

    // Two stair nodes on same Y=300, X differs by 100
    const a = try g.addNode(.{ .x = 100, .y = 300 }, true);
    const b = try g.addNode(.{ .x = 200, .y = 300 }, true);

    // Should have Y-axis stair connection
    const a_edges = g.getEdges(a);
    try std.testing.expect(a_edges.len >= 1);

    var has_b = false;
    for (a_edges) |e| {
        if (e.to == b) has_b = true;
    }
    try std.testing.expect(has_b);
}

test "non-stair nodes on same Y connect via walking" {
    var g = Graph.init(std.testing.allocator, test_config);
    defer g.deinit();

    // Y-axis (same Y, horizontal, same floor) is a regular walk connection —
    // it does NOT require a stair. Two non-stair nodes on the same Y axis
    // within max_horizontal_distance should connect.
    const a = try g.addNode(.{ .x = 100, .y = 100 }, false);
    const b = try g.addNode(.{ .x = 200, .y = 100 }, false);

    const a_edges = g.getEdges(a);
    try std.testing.expectEqual(@as(usize, 1), a_edges.len);
    try std.testing.expectEqual(b, a_edges[0].to);
}

test "stair connection respects max_horizontal_distance" {
    var g = Graph.init(std.testing.allocator, test_config);
    defer g.deinit();

    // Two stair nodes on same Y but 200 apart (exceeds max_horizontal_distance=150)
    const a = try g.addNode(.{ .x = 100, .y = 300 }, true);
    _ = try g.addNode(.{ .x = 300, .y = 300 }, true);

    try std.testing.expectEqual(@as(usize, 0), g.getEdges(a).len);
}

test "same Y nearest-neighbor wins regardless of stair flag" {
    // Y-axis connects via walking (stair flag is irrelevant). The
    // nearest-neighbor rule still applies: A at x=100 reaches C at
    // x=180 (dist 80) instead of B at x=200 (dist 100), because C
    // is nearer on the positive X direction. The stair flags on A
    // and C are incidental — what we're really asserting is the
    // nearest-neighbor tiebreaker on the same floor.
    var g = Graph.init(std.testing.allocator, test_config);
    defer g.deinit();

    const a = try g.addNode(.{ .x = 100, .y = 300 }, true);
    _ = try g.addNode(.{ .x = 200, .y = 300 }, false);
    const c = try g.addNode(.{ .x = 180, .y = 300 }, true);

    const a_edges = g.getEdges(a);
    var has_c = false;
    for (a_edges) |e| {
        if (e.to == c) has_c = true;
    }
    try std.testing.expect(has_c);
}

// --- removeNode ---

test "removes edges when node is removed" {
    var g = Graph.init(std.testing.allocator, test_config);
    defer g.deinit();

    // Stairs so the X-axis pair connects under new semantics.
    const a = try g.addNode(.{ .x = 100, .y = 100 }, true);
    const b = try g.addNode(.{ .x = 100, .y = 200 }, true);

    // Verify connected
    try std.testing.expectEqual(@as(usize, 1), g.getEdges(a).len);
    try std.testing.expectEqual(@as(usize, 1), g.getEdges(b).len);

    g.removeNode(a);

    // B should have no edges to A anymore
    try std.testing.expectEqual(@as(usize, 0), g.getEdges(b).len);
    // Node count decreases
    try std.testing.expectEqual(@as(u32, 1), g.nodeCount());
}

test "sets dirty flag on removeNode" {
    var g = Graph.init(std.testing.allocator, test_config);
    defer g.deinit();

    _ = try g.addNode(.{ .x = 100, .y = 100 }, false);
    g.dirty = false;

    g.removeNode(0);
    try std.testing.expect(g.dirty);
}

test "totalSlots includes tombstones, nodeCount does not" {
    var g = Graph.init(std.testing.allocator, test_config);
    defer g.deinit();

    _ = try g.addNode(.{ .x = 100, .y = 100 }, false); // node 0
    _ = try g.addNode(.{ .x = 100, .y = 200 }, false); // node 1
    _ = try g.addNode(.{ .x = 100, .y = 300 }, false); // node 2

    try std.testing.expectEqual(@as(u32, 3), g.nodeCount());
    try std.testing.expectEqual(@as(u32, 3), g.totalSlots());

    g.removeNode(1); // tombstone at slot 1

    try std.testing.expectEqual(@as(u32, 2), g.nodeCount());
    try std.testing.expectEqual(@as(u32, 3), g.totalSlots()); // still 3 slots
    try std.testing.expect(g.isRemoved(1));
    try std.testing.expect(!g.isRemoved(0));
    try std.testing.expect(!g.isRemoved(2));
}

test "stair connects at distance 250 with max_horizontal_distance=300" {
    const wide_config = Config{
        .max_vertical_distance = 200.0,
        .max_horizontal_distance = 300.0,
        .axis_tolerance = 1.0,
    };
    var g = Graph.init(std.testing.allocator, wide_config);
    defer g.deinit();

    // Two stair nodes 250 apart on same Y (like the game's x=150 → x=400)
    const a = try g.addNode(.{ .x = 150, .y = 300 }, true);
    const b = try g.addNode(.{ .x = 400, .y = 300 }, true);

    const a_edges = g.getEdges(a);
    try std.testing.expectEqual(@as(usize, 1), a_edges.len);
    try std.testing.expectEqual(b, a_edges[0].to);
    try std.testing.expectApproxEqAbs(@as(f32, 250.0), a_edges[0].cost, 0.01);
}

test "stair does NOT connect at distance 250 with max_horizontal_distance=150" {
    var g = Graph.init(std.testing.allocator, test_config); // max_horizontal_distance=150
    defer g.deinit();

    const a = try g.addNode(.{ .x = 150, .y = 300 }, true);
    _ = try g.addNode(.{ .x = 400, .y = 300 }, true);

    // Should NOT connect (250 > 150)
    try std.testing.expectEqual(@as(usize, 0), g.getEdges(a).len);
}

test "removed node is skipped by addNode connections" {
    var g = Graph.init(std.testing.allocator, test_config);
    defer g.deinit();

    const a = try g.addNode(.{ .x = 100, .y = 100 }, false);
    _ = try g.addNode(.{ .x = 100, .y = 200 }, false);

    g.removeNode(a);

    // New node on same X should NOT connect to removed node
    const c = try g.addNode(.{ .x = 100, .y = 150 }, false);
    const c_edges = g.getEdges(c);

    for (c_edges) |e| {
        try std.testing.expect(e.to != a);
    }
}
