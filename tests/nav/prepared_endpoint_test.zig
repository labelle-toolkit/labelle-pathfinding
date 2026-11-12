const std = @import("std");
const testing = std.testing;
const pathfinder = @import("pathfinder");
const CMN = pathfinder.ClosestMovementNode;

const initial = CMN.Stamp{ .world_revision = 1, .entity_id = 42, .entity_generation = 0, .position_revision = 1, .position_slot = 0, .graph_revision = 1 };
const node_zero = CMN.Resolution{ .node_entity = 7, .node_id = 0, .distance = 0 };

test "CMN defaults and legacy writes stay pending; node zero can be published" {
    var cmn = CMN{ .node_entity = 7, .node_id = 0 };
    try testing.expect(!cmn.ready(initial));
    try testing.expect(!cmn.publish(.{}, .{}, node_zero));
    try testing.expect(cmn.publish(initial, initial, node_zero));
    try testing.expect(cmn.ready(initial));
    cmn.invalidate(.parent);
    try testing.expect(!cmn.current(initial));
    try testing.expectEqual(@as(u64, 7), cmn.node_entity);
    try testing.expectEqual(@as(u32, 0), cmn.node_id);
    try testing.expectEqualDeep(initial, cmn.last_ready_stamp);
    try testing.expectEqual(CMN.Invalidation.parent, cmn.invalidation);
}

test "publication rejects changed identity, position, world or graph without overwriting newer data" {
    inline for (std.meta.fields(CMN.Stamp)) |field| {
        var changed = initial;
        @field(changed, field.name) += 1;
        var cmn = CMN{};
        try testing.expect(cmn.publish(initial, initial, node_zero));
        try testing.expect(!cmn.ready(changed));
        try testing.expect(cmn.publish(changed, changed, .{ .node_entity = 8, .node_id = 1, .distance = 2 }));
        const newer = cmn;
        try testing.expect(!cmn.publish(initial, changed, node_zero));
        try testing.expectEqualDeep(newer, cmn);
    }
}

test "off graph is completed work until inputs change and keeps last node's original stamp" {
    var cmn = CMN{};
    try testing.expect(cmn.publish(initial, initial, node_zero));
    var moved = initial;
    moved.position_revision += 1;
    cmn.invalidate(.position);
    try testing.expect(cmn.publish(moved, moved, null));
    try testing.expect(cmn.current(moved));
    try testing.expect(!cmn.ready(moved));
    try testing.expect(!cmn.current(initial));
    try testing.expectEqualDeep(initial, cmn.last_ready_stamp);
    try testing.expectEqual(@as(u64, 7), cmn.node_entity);
    moved.graph_revision += 1;
    try testing.expect(!cmn.current(moved));
}

test "invalid resolution distances cannot publish a ready endpoint" {
    for ([_]f32{ -1, std.math.inf(f32), std.math.nan(f32) }) |distance| {
        var cmn = CMN{};
        var resolution = node_zero;
        resolution.distance = distance;
        try testing.expect(!cmn.publish(initial, initial, resolution));
        try testing.expect(!cmn.ready(initial));
    }
}

test "prepared table queries do not build or repair and reject dirty, removed and disconnected nodes" {
    var pf = pathfinder.PathfinderWith(u64, struct {}).init(testing.allocator, .{ .max_vertical_distance = 200, .max_horizontal_distance = 150 });
    defer pf.deinit();
    const a = try pf.addNode(.{ .x = 0, .y = 0 }, false);
    const b = try pf.addNode(.{ .x = 20, .y = 0 }, false);
    const isolated = try pf.addNode(.{ .x = 1000, .y = 1000 }, false);
    try testing.expectEqual(null, pf.preparedNodeDistance(a, b));
    try testing.expect(pf.graph.dirty);
    try testing.expectEqual(null, pf.fw);
    try testing.expect(pf.prepareDistanceTable());
    try testing.expectEqual(@as(?f32, 20), pf.preparedNodeDistance(a, b));
    try testing.expectEqual(@as(?f32, 0), pf.preparedNodeDistance(a, a));
    try testing.expectEqual(null, pf.preparedNodeDistance(a, isolated));
    try testing.expectEqual(null, pf.preparedNodeDistance(a, 10000));
    pf.removeNode(b);
    try testing.expectEqual(null, pf.preparedNodeDistance(a, a));
    try testing.expect(pf.graph.dirty);
    try testing.expect(pf.prepareDistanceTable());
    try testing.expectEqual(null, pf.preparedNodeDistance(b, b));
    try testing.expectEqual(@as(?f32, 0), pf.preparedNodeDistance(a, a));
}
