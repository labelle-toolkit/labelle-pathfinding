// v4 surface tests — the ctx settle callbacks (engine level) and the
// pure direct-walk kinematics. The full Controller flows (rehydration
// sweep, settle events, CMN epoch sweep) are exercised end-to-end by
// the consuming game's integration suites (flying-platform's bandit
// scenes + save_load_smoke) — the Controller is duck-typed on the full
// game API, which this repo deliberately doesn't mock.

const std = @import("std");
const pathfinder = @import("pathfinder");
const Position = @import("labelle-core").Position;

const PathfinderWith = pathfinder.PathfinderWith;
const Config = pathfinder.Config;
const controller = pathfinder.controller;

const test_config = Config{
    .max_vertical_distance = 200.0,
    .max_horizontal_distance = 150.0,
    .axis_tolerance = 1.0,
};

/// MockCtx WITH the v4 settle callbacks — records what fired.
const CallbackCtx = struct {
    positions: std.AutoHashMap(u64, Position),
    allocator: std.mem.Allocator,
    arrived: std.ArrayListUnmanaged(Settle) = .empty,
    invalidated: std.ArrayListUnmanaged(Settle) = .empty,

    const Settle = struct { entity: u64, goal_node: u32 };

    fn init(allocator: std.mem.Allocator) CallbackCtx {
        return .{
            .positions = std.AutoHashMap(u64, Position).init(allocator),
            .allocator = allocator,
        };
    }

    fn deinit(self: *CallbackCtx) void {
        self.positions.deinit();
        self.arrived.deinit(self.allocator);
        self.invalidated.deinit(self.allocator);
    }

    pub fn getEntityPosition(self: *CallbackCtx, entity: u64) ?Position {
        return self.positions.get(entity);
    }

    pub fn moveEntity(self: *CallbackCtx, entity: u64, dx: f32, dy: f32) void {
        if (self.positions.getPtr(entity)) |pos| {
            pos.x += dx;
            pos.y += dy;
        }
    }

    pub fn onArrived(self: *CallbackCtx, entity: u64, goal_node: u32) void {
        // Test recorder: OOM must fail the test loudly, not silently
        // drop a settle record.
        self.arrived.append(self.allocator, .{ .entity = entity, .goal_node = goal_node }) catch unreachable;
    }

    pub fn onPathInvalidated(self: *CallbackCtx, entity: u64, goal_node: u32) void {
        self.invalidated.append(self.allocator, .{ .entity = entity, .goal_node = goal_node }) catch unreachable;
    }
};

test "tick fires onArrived with the goal node when a walk completes" {
    const Pf = PathfinderWith(u64, struct {});
    var pf = Pf.init(std.testing.allocator, test_config);
    defer pf.deinit();

    const a = try pf.addNode(.{ .x = 100, .y = 100 }, true);
    const b = try pf.addNode(.{ .x = 100, .y = 200 }, true);

    var ctx = CallbackCtx.init(std.testing.allocator);
    defer ctx.deinit();
    try ctx.positions.put(7, .{ .x = 100, .y = 100 });

    _ = try pf.navigate(7, a, b, 1000.0);
    // Generous dt budget: 100 px at 1000 px/s needs 0.1 s.
    var i: usize = 0;
    while (i < 60 and pf.isNavigating(7)) : (i += 1) {
        pf.tick(&ctx, 0.016);
    }

    try std.testing.expectEqual(@as(usize, 1), ctx.arrived.items.len);
    try std.testing.expectEqual(@as(u64, 7), ctx.arrived.items[0].entity);
    try std.testing.expectEqual(b, ctx.arrived.items[0].goal_node);
    try std.testing.expectEqual(@as(usize, 0), ctx.invalidated.items.len);
}

test "tick fires onPathInvalidated when the goal dies and no reroute exists" {
    const Pf = PathfinderWith(u64, struct {});
    var pf = Pf.init(std.testing.allocator, test_config);
    defer pf.deinit();

    const a = try pf.addNode(.{ .x = 100, .y = 100 }, true);
    const b = try pf.addNode(.{ .x = 100, .y = 200 }, true);
    const c = try pf.addNode(.{ .x = 100, .y = 300 }, true);
    _ = a;

    var ctx = CallbackCtx.init(std.testing.allocator);
    defer ctx.deinit();
    try ctx.positions.put(9, .{ .x = 100, .y = 100 });

    _ = try pf.navigate(9, 0, c, 10.0); // slow walker, long route
    pf.tick(&ctx, 0.016);

    // Sever the route mid-walk: the only path to c runs through b.
    pf.removeNode(b);
    pf.removeNode(c);
    pf.tick(&ctx, 0.016);

    try std.testing.expectEqual(@as(usize, 1), ctx.invalidated.items.len);
    try std.testing.expectEqual(@as(u64, 9), ctx.invalidated.items[0].entity);
    try std.testing.expect(!pf.isNavigating(9));
}

test "a one-waypoint route walks the rest of a segment and arrives (#60)" {
    const Pf = PathfinderWith(u64, struct {});
    var pf = Pf.init(std.testing.allocator, test_config);
    defer pf.deinit();

    const a = try pf.addNode(.{ .x = 100, .y = 100 }, true);
    _ = try pf.addNode(.{ .x = 100, .y = 200 }, true);

    var ctx = CallbackCtx.init(std.testing.allocator);
    defer ctx.deinit();
    // 40 px short of `a`, as a re-issue finds a walker on its last leg.
    try ctx.positions.put(7, .{ .x = 100, .y = 140 });

    _ = try pf.navigate(7, a, a, 60.0);
    var i: usize = 0;
    while (i < 120 and pf.isNavigating(7)) : (i += 1) {
        const before = ctx.positions.get(7).?;
        pf.tick(&ctx, 0.016);
        // Walks, never jumps: no step beyond the engine's 2 px waypoint
        // snap (speed·dt is ~1 px here; the jump was the whole 40 px).
        try std.testing.expect(before.y - ctx.positions.get(7).?.y <= 2.0 + 0.001);
    }

    try std.testing.expectEqual(@as(usize, 1), ctx.arrived.items.len);
    try std.testing.expectEqual(a, ctx.arrived.items[0].goal_node);
    try std.testing.expectEqual(@as(f32, 100), ctx.positions.get(7).?.y);
}

test "a one-waypoint route is invalidated when its node goes away (#60)" {
    const Pf = PathfinderWith(u64, struct {});
    var pf = Pf.init(std.testing.allocator, test_config);
    defer pf.deinit();

    const a = try pf.addNode(.{ .x = 100, .y = 100 }, true);
    _ = try pf.addNode(.{ .x = 900, .y = 900 }, false);

    var ctx = CallbackCtx.init(std.testing.allocator);
    defer ctx.deinit();
    try ctx.positions.put(9, .{ .x = 100, .y = 140 });

    _ = try pf.navigate(9, a, a, 10.0);
    pf.tick(&ctx, 0.016);
    pf.removeNode(a);
    pf.tick(&ctx, 0.016);

    try std.testing.expectEqual(@as(usize, 0), ctx.arrived.items.len);
    try std.testing.expectEqual(@as(usize, 1), ctx.invalidated.items.len);
    try std.testing.expect(!pf.isNavigating(9));
}

test "plain ctx without settle callbacks still compiles and ticks" {
    const Pf = PathfinderWith(u64, struct {});
    var pf = Pf.init(std.testing.allocator, test_config);
    defer pf.deinit();

    const Plain = struct {
        pos: Position = .{ .x = 0, .y = 0 },
        pub fn getEntityPosition(self: *@This(), entity: u64) ?Position {
            _ = entity;
            return self.pos;
        }
        pub fn moveEntity(self: *@This(), entity: u64, dx: f32, dy: f32) void {
            _ = entity;
            self.pos.x += dx;
            self.pos.y += dy;
        }
    };
    var ctx = Plain{};
    pf.tick(&ctx, 0.016);
}

test "directStep: within arrival radius reports arrived" {
    const step = controller.directStep(
        .{ .x = 100, .y = 100 },
        .{ .x = 103, .y = 100 },
        200.0,
        0.016,
    );
    try std.testing.expect(step == .arrived);
}

test "directStep: clamps to speed*dt and never overshoots" {
    // 100 px away, speed 200, dt 0.016 → 3.2 px step toward target.
    const step = controller.directStep(
        .{ .x = 0, .y = 0 },
        .{ .x = 100, .y = 0 },
        200.0,
        0.016,
    );
    try std.testing.expect(step == .move);
    try std.testing.expectApproxEqAbs(@as(f32, 3.2), step.move.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), step.move.y, 0.001);

    // Big dt: remaining distance < speed*dt → lands exactly on target,
    // never past it.
    const snap = controller.directStep(
        .{ .x = 0, .y = 0 },
        .{ .x = 100, .y = 0 },
        200.0,
        10.0,
    );
    try std.testing.expect(snap == .move);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), snap.move.x, 0.001);
}

test "directStep: diagonal step normalizes direction" {
    const step = controller.directStep(
        .{ .x = 0, .y = 0 },
        .{ .x = 30, .y = 40 }, // dist 50
        100.0,
        0.1, // move_dist 10 → (6, 8)
    );
    try std.testing.expect(step == .move);
    try std.testing.expectApproxEqAbs(@as(f32, 6.0), step.move.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 8.0), step.move.y, 0.001);
}

test "a walk crosses an authored diagonal link as one straight leg" {
    const Pf = PathfinderWith(u64, struct {});
    var pf = Pf.init(std.testing.allocator, test_config);
    defer pf.deinit();

    // A raised deck at y=28, steps down to the main deck at y=0.
    const deck_far = try pf.addNode(.{ .x = 0, .y = 28 }, false);
    const step_top = try pf.addNode(.{ .x = 88, .y = 28 }, false);
    const step_bottom = try pf.addNode(.{ .x = 126, .y = 0 }, false);
    const main = try pf.addNode(.{ .x = 176, .y = 0 }, false);
    try pf.addLink(step_top, step_bottom);

    var ctx = CallbackCtx.init(std.testing.allocator);
    defer ctx.deinit();
    try ctx.positions.put(3, .{ .x = 0, .y = 28 });

    const path = (try pf.navigate(3, deck_far, main, 1000.0)).?;
    try std.testing.expectEqualSlices(u32, &.{ deck_far, step_top, step_bottom, main }, path.node_path);

    var i: usize = 0;
    while (i < 100 and ctx.arrived.items.len == 0) : (i += 1) pf.tick(&ctx, 0.016);
    try std.testing.expectEqual(@as(usize, 1), ctx.arrived.items.len);
    const end = ctx.positions.get(3).?;
    try std.testing.expectApproxEqAbs(@as(f32, 176), end.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0), end.y, 0.01);
}
