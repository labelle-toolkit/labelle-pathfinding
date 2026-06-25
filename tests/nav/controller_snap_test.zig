//! Coverage for the `MAX_NODE_SNAP_DISTANCE` gate added in #367.
//! Per Copilot review: assert that `findNearestNodeInState` returns
//! `null` for entities beyond the cap and still resolves entities
//! within it. Guards against accidental regressions in either
//! direction (loosening the cap silently re-introduces the
//! "walking on air" symptom; tightening it would orphan legitimate
//! in-room entities).

const std = @import("std");
const pathfinder = @import("pathfinder");

const State = pathfinder.controller.State;
const findNearestNodeInState = pathfinder.controller.findNearestNodeInState;
const MAX_NODE_SNAP_DISTANCE = pathfinder.controller.MAX_NODE_SNAP_DISTANCE;

fn newState() !State {
    var st = State.init(std.testing.allocator);
    // Single node at origin — distance from any probe point is the
    // probe's Euclidean magnitude. Keeps the test math obvious.
    _ = try st.pf.graph.addNode(.{ .x = 0, .y = 0 }, false);
    return st;
}

// All probes in this file are placed *above* the node (higher Y in
// the world's Y-up convention) so the at-or-below Y filter accepts
// the node — the snap-distance cap is what we're isolating, not the
// Y filter.

test "findNearestNodeInState returns the node when probe is within snap cap" {
    var st = try newState();
    defer st.deinit();

    // ~51 px away (probe at (50, 10) vs node at (0, 0)) — well under
    // the 100-px cap.
    const result = findNearestNodeInState(&st, 50.0, 10.0);
    try std.testing.expect(result != null);
}

test "findNearestNodeInState returns null when probe is beyond snap cap" {
    var st = try newState();
    defer st.deinit();

    // ~141 px away (sqrt(2) × 100) — past the 100-px cap.
    const result = findNearestNodeInState(&st, 100.0, 100.0);
    try std.testing.expect(result == null);
}

test "findNearestNodeInState honors the cap exactly at the boundary" {
    var st = try newState();
    defer st.deinit();

    // Probe at distance == MAX_NODE_SNAP_DISTANCE on the same Y as
    // the node. The check is `>` (strict), so exactly-at is still
    // accepted.
    const result_at = findNearestNodeInState(&st, MAX_NODE_SNAP_DISTANCE, 0.0);
    try std.testing.expect(result_at != null);

    // 1 px past the cap — rejected.
    const result_past = findNearestNodeInState(&st, MAX_NODE_SNAP_DISTANCE + 1.0, 0.0);
    try std.testing.expect(result_past == null);
}

test "findNearestNodeInState returns null with no nodes in the graph" {
    var st = State.init(std.testing.allocator);
    defer st.deinit();

    // Empty graph — no nodes to snap to, regardless of probe position.
    const result = findNearestNodeInState(&st, 0.0, 0.0);
    try std.testing.expect(result == null);
}
