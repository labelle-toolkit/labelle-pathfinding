const std = @import("std");
const pathfinder = @import("pathfinder");

const CachedNearest = pathfinder.controller.CachedNearest;
const cachedNearestStillValid = pathfinder.controller.cachedNearestStillValid;
const CACHE_POS_THRESHOLD = pathfinder.controller.CACHE_POS_THRESHOLD;
const Y_FILTER_EPS = pathfinder.controller.Y_FILTER_EPS;

// Entity at (100, 50), cached node at y=48 (2 px above the entity).
// The node passes the Y-filter (`node_y <= entity_y + 5`) by 7 px of
// slack, so lateral-drift tests can move around without tripping the
// Y branch.
fn fixtureOnFloor() CachedNearest {
    return .{
        .node_id = 7,
        .cached_x = 100.0,
        .cached_y = 50.0,
        .cached_node_y = 48.0,
    };
}

test "cachedNearestStillValid: same position hits" {
    try std.testing.expect(cachedNearestStillValid(fixtureOnFloor(), 100.0, 50.0));
}

test "cachedNearestStillValid: drift under in-plane threshold hits" {
    // ~10 px in-plane drift — both conditions satisfied.
    try std.testing.expect(cachedNearestStillValid(fixtureOnFloor(), 108.0, 52.0));
}

test "cachedNearestStillValid: drift over in-plane threshold misses" {
    // 20 px horizontal drift — beyond CACHE_POS_THRESHOLD.
    try std.testing.expect(!cachedNearestStillValid(fixtureOnFloor(), 120.0, 50.0));
}

test "cachedNearestStillValid: exactly at in-plane threshold misses (half-open bound)" {
    // 15 px horizontal drift — `<` bound, so exactly-at is a miss.
    try std.testing.expect(!cachedNearestStillValid(fixtureOnFloor(), 115.0, 50.0));
}

test "cachedNearestStillValid: node still inside Y-filter after entity descends slightly" {
    // Entity moved down 2 px; cached node at y=48 is now 4 px above
    // (48 <= 52+5 = 57), still within filter.
    try std.testing.expect(cachedNearestStillValid(fixtureOnFloor(), 100.0, 52.0));
}

test "cachedNearestStillValid: node falls off Y-filter when entity ascends enough" {
    // Entity moves up to y=42. Cached node at y=48 is now 6 px above
    // the entity — filter rejects it (`48 > 42 + 5`). Must rescan.
    try std.testing.expect(!cachedNearestStillValid(fixtureOnFloor(), 100.0, 42.0));
}

test "cachedNearestStillValid: node exactly at the Y-filter bound still hits (inclusive)" {
    // Node at y=48, entity at y=43 — `48 <= 43+5 = 48`, inclusive
    // boundary, filter still accepts it. Matches the `npos.y > y + Y_FILTER_EPS`
    // check in findNearestNodeInState (strict `>`).
    try std.testing.expect(cachedNearestStillValid(fixtureOnFloor(), 100.0, 43.0));
}

test "cachedNearestStillValid: entity moves down far from cached node" {
    // Entity descends to y=80. Node at y=48 is 32 px above — well
    // inside the Y-filter. But entity in-plane drift from (100,50)
    // to (100,80) is 30 px, over the in-plane threshold. Must rescan.
    try std.testing.expect(!cachedNearestStillValid(fixtureOnFloor(), 100.0, 80.0));
}

// ---------------------------------------------------------------------------
// #493: nearest_node_cache prune-on-destroy
// ---------------------------------------------------------------------------

const State = pathfinder.controller.State;
const pruneNearestNodeCacheBy = pathfinder.controller.pruneNearestNodeCacheBy;

/// Synthetic alive-probe: an entity is "alive" iff its id is NOT in the
/// `dead` set. Stands in for the Controller's `ecs.entityExists` check
/// so the prune logic is testable without a live ECS backend.
const DeadSetProbe = struct {
    dead: *const std.AutoHashMap(u64, void),
    pub fn alive(self: @This(), entity_id: u64) bool {
        return !self.dead.contains(entity_id);
    }
};

fn putCacheEntry(st: *State, entity_id: u64) !void {
    try st.nearest_node_cache.put(entity_id, .{
        .node_id = 1,
        .cached_x = 0,
        .cached_y = 0,
        .cached_node_y = 0,
    });
}

test "pruneNearestNodeCache: drops only entries whose entity is dead" {
    const allocator = std.testing.allocator;
    var st = State.init(allocator);
    defer st.deinit();

    try putCacheEntry(&st, 10);
    try putCacheEntry(&st, 20);
    try putCacheEntry(&st, 30);

    var dead = std.AutoHashMap(u64, void).init(allocator);
    defer dead.deinit();
    try dead.put(20, {}); // 20 was destroyed

    pruneNearestNodeCacheBy(&st, DeadSetProbe{ .dead = &dead });

    try std.testing.expectEqual(@as(usize, 2), st.nearest_node_cache.count());
    try std.testing.expect(st.nearest_node_cache.contains(10));
    try std.testing.expect(!st.nearest_node_cache.contains(20));
    try std.testing.expect(st.nearest_node_cache.contains(30));
}

test "pruneNearestNodeCache: bounds the cache to the live set under churn" {
    const allocator = std.testing.allocator;
    var st = State.init(allocator);
    defer st.deinit();

    var dead = std.AutoHashMap(u64, void).init(allocator);
    defer dead.deinit();

    // Simulate heavy entity churn: 100 entities flow through distance()
    // (populating the cache), then all but the last 5 are destroyed.
    var i: u64 = 0;
    while (i < 100) : (i += 1) try putCacheEntry(&st, i);
    i = 0;
    while (i < 95) : (i += 1) try dead.put(i, {});

    pruneNearestNodeCacheBy(&st, DeadSetProbe{ .dead = &dead });

    // Without the prune the cache would stay at 100 (the churn bug);
    // with it, it tracks the 5 live entities.
    try std.testing.expectEqual(@as(usize, 5), st.nearest_node_cache.count());
}

test "pruneNearestNodeCache: no-op when every entity is alive" {
    const allocator = std.testing.allocator;
    var st = State.init(allocator);
    defer st.deinit();

    try putCacheEntry(&st, 1);
    try putCacheEntry(&st, 2);

    var dead = std.AutoHashMap(u64, void).init(allocator);
    defer dead.deinit();

    pruneNearestNodeCacheBy(&st, DeadSetProbe{ .dead = &dead });
    try std.testing.expectEqual(@as(usize, 2), st.nearest_node_cache.count());
}

test "thresholds match documentation" {
    // Guard against accidental bumps — these are tuned against the
    // game's observed node spacing + the Y-filter already used in
    // `findNearestNodeInState`. If either needs to change, update the
    // doc comment in controller.zig alongside this test.
    try std.testing.expectEqual(@as(f32, 15.0), CACHE_POS_THRESHOLD);
    try std.testing.expectEqual(@as(f32, 5.0), Y_FILTER_EPS);
}
