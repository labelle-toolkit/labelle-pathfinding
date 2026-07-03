//! Coverage for the first-class reachability query surface added for
//! issue #48 (Packs query-pack exemplar). Exercises the State-level
//! `nodesReachable` helper that single-sources the semantics behind
//! `Controller.reachable` / `reachableNode` / `reachablePosition`.
//!
//! The Controller's game-facing methods (`reachable(game, a, b)`, …)
//! need a live ECS backend to resolve entities → nodes, so they're not
//! unit-tested here; `Controller.reachable` is by construction
//! `distance(a, b) != null`, and both `distance` and `nodesReachable`
//! bottom out in the SAME `pf.isReachable` / `pf.distance` matrix
//! lookup — the consistency asserted below is what guarantees the
//! entity-level wrappers agree with `distance`.

const std = @import("std");
const pathfinder = @import("pathfinder");

const State = pathfinder.controller.State;
const nodesReachable = pathfinder.controller.nodesReachable;
const INF = pathfinder.INF;

/// Two connected stair nodes on X=100 (y=100/200, dist 100 < the
/// State's 200-px vertical cap) plus one isolated node far off on its
/// own axis. Node ids: 0 and 1 connected; 2 disconnected.
fn connectedPairPlusIsolated() !State {
    var st = State.init(std.testing.allocator);
    _ = try st.pf.addNode(.{ .x = 100, .y = 100 }, true); // node 0 (stair)
    _ = try st.pf.addNode(.{ .x = 100, .y = 200 }, true); // node 1 (stair)
    _ = try st.pf.addNode(.{ .x = 500, .y = 500 }, true); // node 2 (isolated)
    return st;
}

test "nodesReachable: connected pair is reachable" {
    var st = try connectedPairPlusIsolated();
    defer st.deinit();

    try std.testing.expect(nodesReachable(&st, 0, 1));
    // Symmetric — the graph is bidirectional.
    try std.testing.expect(nodesReachable(&st, 1, 0));
}

test "nodesReachable: disconnected pair is not reachable" {
    var st = try connectedPairPlusIsolated();
    defer st.deinit();

    try std.testing.expect(!nodesReachable(&st, 0, 2));
    try std.testing.expect(!nodesReachable(&st, 2, 1));
}

test "nodesReachable: pre-graph (no nodes) is false" {
    var st = State.init(std.testing.allocator);
    defer st.deinit();

    // Empty graph — the pre-graph negative answer, regardless of ids.
    try std.testing.expect(!nodesReachable(&st, 0, 0));
    try std.testing.expect(!nodesReachable(&st, 0, 1));
}

test "nodesReachable: a node is reachable from itself" {
    var st = try connectedPairPlusIsolated();
    defer st.deinit();

    // Even the isolated node reaches itself (distance 0).
    try std.testing.expect(nodesReachable(&st, 2, 2));
}

test "nodesReachable: out-of-range node id is false" {
    var st = try connectedPairPlusIsolated();
    defer st.deinit();

    // Only 3 slots (ids 0..2) — id 99 is past totalSlots().
    try std.testing.expect(!nodesReachable(&st, 0, 99));
    try std.testing.expect(!nodesReachable(&st, 99, 0));
}

test "nodesReachable: tombstoned node id is false" {
    var st = try connectedPairPlusIsolated();
    defer st.deinit();

    // Reachable before removal…
    try std.testing.expect(nodesReachable(&st, 0, 1));
    // …tombstone node 1 and the guard rejects it (no matrix panic).
    st.pf.removeNode(1);
    try std.testing.expect(!nodesReachable(&st, 0, 1));
    try std.testing.expect(!nodesReachable(&st, 1, 0));
}

test "nodesReachable agrees with distance() != INF for every pair" {
    var st = try connectedPairPlusIsolated();
    defer st.deinit();

    // The load-bearing consistency check: `reachable` must always
    // mean exactly `distance != null`. Since both go through the same
    // pf matrix, assert it holds for the full pair space.
    const slots = st.pf.graph.totalSlots();
    var a: u32 = 0;
    while (a < slots) : (a += 1) {
        var b: u32 = 0;
        while (b < slots) : (b += 1) {
            const via_distance = st.pf.distance(a, b) != INF;
            try std.testing.expectEqual(via_distance, nodesReachable(&st, a, b));
        }
    }
}
