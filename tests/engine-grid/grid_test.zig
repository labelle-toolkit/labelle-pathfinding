const std = @import("std");
const engine = @import("engine");
const nav = @import("pathfinder");
const core = engine.core;
const testing = std.testing;

const Event = union(enum) {
    pathfinder__arrived: nav.Events.arrived,
    pathfinder__navigation_failed: nav.Events.navigation_failed,
    pathfinder__grid_changed: nav.Events.grid_changed,
};

const Receiver = struct {
    ctx: engine.HookContext = .{},
    last: ?nav.Events.arrived = null,
    failures: usize = 0,
    changes: usize = 0,
    last_change: ?nav.Events.grid_changed = null,

    pub fn component_changed(self: *Receiver, p: engine.ComponentChangeInfo(u32)) void {
        nav.Controller.componentChanged(self.ctx.gameAs(Game), p);
    }

    pub fn pathfinder__arrived(self: *Receiver, p: nav.Events.arrived) void {
        self.last = p;
    }

    pub fn pathfinder__navigation_failed(self: *Receiver, p: nav.Events.navigation_failed) void {
        if (p.reason == .path_invalidated) self.failures += 1;
    }

    pub fn pathfinder__grid_changed(self: *Receiver, event: nav.Events.grid_changed) void {
        self.changes += 1;
        self.last_change = event;
    }
};

const ECS = core.MockEcsBackend(u32);
const Hook = engine.MergeHookPayloads(.{ engine.HookPayload(u32), Event });
const Hooks = engine.MergeHooks(Hook, .{*Receiver});
const Components = engine.ComponentRegistry(.{
    .NavGrid = nav.NavGrid,
    .NavCost = nav.NavCost,
    .NavObstacle = nav.NavObstacle,
    .Navigating = nav.Navigating,
});
const Game = engine.GameConfig(core.StubRender(u32), ECS, engine.StubInput, engine.StubAudio, engine.StubVideo, engine.StubGui, *Hooks, core.StubLogSink, Components, &.{}, Event);
const Controller = nav.Controller;

fn addAt(game: *Game, x: f32, y: f32) u32 {
    const id = game.createEntity();
    game.setPosition(id, .{ .x = x, .y = y });
    return id;
}

fn addGrid(game: *Game, cols: u32, rows: u32) void {
    game.addComponent(game.createEntity(), nav.NavGrid{ .cols = cols, .rows = rows, .cell = 10 });
}

test "hooks update occupancy after writes, removals and destruction without polling" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    var receiver: Receiver = .{};
    var hooks: Hooks = .{ .receivers = .{&receiver} };
    game.setHooks(&hooks);
    addGrid(&game, 5, 3);
    const mover = addAt(&game, 5, 15);
    try Controller.setup(&game);
    defer Controller.deinit(&game);

    const obstacle = addAt(&game, 25, 15);
    game.addComponent(obstacle, nav.NavObstacle{ .width = 8, .height = 8 });
    game.addComponent(obstacle, nav.NavCost{ .width = 8, .height = 8, .cost = 33 });
    try testing.expect(Controller.isBlocked(&game, .{ .x = 25, .y = 15 }));
    try testing.expect(Controller.gridReachableAdjacent(&game, mover, obstacle));
    try testing.expect(Controller.navigateAdjacent(&game, mover, obstacle) == .accepted);
    Controller.drawGridGizmos(&game);
    Controller.advance(&game, 1);
    game.dispatchEvents();
    try testing.expectEqual(@as(u32, 1), receiver.last.?.destination.?.grid.col);

    game.setField(core.Position, .x, obstacle, 35);
    try testing.expect(!Controller.isBlocked(&game, .{ .x = 25, .y = 15 }));
    try testing.expect(Controller.isBlocked(&game, .{ .x = 35, .y = 15 }));
    game.removeComponent(obstacle, nav.NavObstacle);
    try testing.expectEqual(@as(?u8, 33), Controller.cellCost(&game, .{ .x = 35, .y = 15 }));
    game.destroyEntity(obstacle);
    try testing.expectEqual(@as(?u8, 10), Controller.cellCost(&game, .{ .x = 35, .y = 15 }));
    const epoch = Controller.gridEpoch(&game);
    Controller.advance(&game, 1);
    try testing.expectEqual(epoch, Controller.gridEpoch(&game));
    game.dispatchEvents();
    try testing.expectEqual(@as(usize, 4), receiver.changes);
}

test "smoothed segment invalidates before movement and a loaded grid order resumes" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    var receiver: Receiver = .{};
    var hooks: Hooks = .{ .receivers = .{&receiver} };
    game.setHooks(&hooks);
    addGrid(&game, 5, 1);
    const mover = addAt(&game, 5, 5);
    try Controller.setup(&game);
    defer Controller.deinit(&game);
    const goal: nav.Position = .{ .x = 45, .y = 5 };
    try testing.expectEqual(@as(?u64, 400), Controller.gridWalkCost(&game, mover, goal));
    try testing.expect(Controller.navigateTo(&game, mover, goal) == .accepted);
    const obstacle = addAt(&game, 25, 5);
    game.addComponent(obstacle, nav.NavObstacle{ .width = 8, .height = 8 });
    Controller.advance(&game, 1);
    game.dispatchEvents();
    try testing.expectEqual(@as(f32, 5), game.getPosition(mover).x);
    try testing.expectEqual(@as(usize, 1), receiver.failures);
    try testing.expect(!game.hasComponent(mover, nav.Navigating));

    game.destroyEntityOnly(obstacle);
    game.addComponent(mover, nav.Navigating{ .mode = .grid, .target_x = goal.x, .target_y = goal.y });
    Controller.advance(&game, 1);
    game.dispatchEvents();
    try testing.expectEqual(goal.x, game.getPosition(mover).x);
    try testing.expectEqual(@as(u64, 0), receiver.last.?.node_entity);
    try testing.expectEqual(@as(u32, 4), receiver.last.?.destination.?.grid.col);
}

test "diagonal support blockage reroutes a grid walk and cancel clears persisted order" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    var receiver: Receiver = .{};
    var hooks: Hooks = .{ .receivers = .{&receiver} };
    game.setHooks(&hooks);
    addGrid(&game, 3, 3);
    const mover = addAt(&game, 5, 5);
    try Controller.setup(&game);
    defer Controller.deinit(&game);
    const goal: nav.Position = .{ .x = 25, .y = 25 };
    try testing.expect(Controller.gridReachable(&game, mover, goal));
    try testing.expect(Controller.navigateTo(&game, mover, goal) == .accepted);
    const obstacle = addAt(&game, 15, 5);
    game.addComponent(obstacle, nav.NavObstacle{ .width = 8, .height = 8 });
    const epoch = Controller.gridEpoch(&game);
    Controller.advance(&game, 0.04);
    try testing.expectEqual(@as(f32, 5), game.getPosition(mover).x);
    try testing.expect(game.getPosition(mover).y > 5);
    try testing.expectEqual(epoch, Controller.gridEpoch(&game));
    Controller.cancel(&game, mover);
    try testing.expect(!Controller.isNavigating(&game, mover));
    Controller.advance(&game, 1);
    try testing.expect(!game.hasComponent(mover, nav.Navigating));
    game.dispatchEvents();
    try testing.expectEqual(@as(usize, 0), receiver.failures);
}

test "blocked goals snap to a reachable cell and direct retargets replace grid walks" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    var receiver: Receiver = .{};
    var hooks: Hooks = .{ .receivers = .{&receiver} };
    game.setHooks(&hooks);
    addGrid(&game, 5, 1);
    const mover = addAt(&game, 5, 5);
    const obstacle = addAt(&game, 35, 5);
    game.addComponent(obstacle, nav.NavObstacle{ .width = 8, .height = 8 });
    try Controller.setup(&game);
    defer Controller.deinit(&game);
    const blocked: nav.Position = .{ .x = 35, .y = 5 };
    try testing.expect(!Controller.gridReachable(&game, mover, blocked));
    try testing.expect(Controller.navigateTo(&game, mover, blocked) == .accepted);
    Controller.advance(&game, 1);
    game.dispatchEvents();
    try testing.expectEqual(@as(u32, 2), receiver.last.?.destination.?.grid.col);
    try testing.expect(Controller.navigateTo(&game, mover, .{ .x = 5, .y = 5 }) == .accepted);
    try testing.expect(Controller.moveTo(&game, mover, .{ .x = 100, .y = 5 }) == .accepted);
    Controller.advance(&game, 1);
    Controller.advance(&game, 1);
    game.dispatchEvents();
    try testing.expectEqual(@as(f32, 100), receiver.last.?.destination.?.direct.x);
    try testing.expect(!Controller.isNavigating(&game, mover));
}

test "a running walk can escape a newly blocked start through a single free edge" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    var receiver: Receiver = .{};
    var hooks: Hooks = .{ .receivers = .{&receiver} };
    game.setHooks(&hooks);
    addGrid(&game, 5, 1);
    const mover = addAt(&game, 15, 5);
    try Controller.setup(&game);
    defer Controller.deinit(&game);
    const goal: nav.Position = .{ .x = 45, .y = 5 };
    try testing.expect(Controller.navigateTo(&game, mover, goal) == .accepted);
    const obstacle = addAt(&game, 15, 5);
    game.addComponent(obstacle, nav.NavObstacle{ .width = 8, .height = 8 });
    try testing.expect(Controller.gridReachable(&game, mover, goal));
    Controller.advance(&game, 0.01);
    try testing.expectEqual(@as(f32, 17), game.getPosition(mover).x);
    Controller.advance(&game, 1);
    game.dispatchEvents();
    try testing.expectEqual(goal.x, game.getPosition(mover).x);
    try testing.expectEqual(@as(usize, 0), receiver.failures);
}

test "invalid configuration rejects commands until a corrected rebuild" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    var receiver: Receiver = .{};
    var hooks: Hooks = .{ .receivers = .{&receiver} };
    game.setHooks(&hooks);
    const cfg = game.createEntity();
    game.addComponent(cfg, nav.NavGrid{ .cols = 3, .rows = 1, .cell = 10 });
    const mover = addAt(&game, 5, 5);
    try Controller.setup(&game);
    defer Controller.deinit(&game);
    const goal: nav.Position = .{ .x = 25, .y = 5 };
    try testing.expect(Controller.navigateTo(&game, mover, goal) == .accepted);
    game.setField(nav.NavGrid, .cell, cfg, 0);
    Controller.rebuildGrid(&game);
    Controller.advance(&game, 1);
    game.dispatchEvents();
    try testing.expectEqual(@as(usize, 1), receiver.failures);
    try testing.expectEqual(nav.Reason.invalid_grid, Controller.navigateTo(&game, mover, goal).rejected);
    game.setField(nav.NavGrid, .cell, cfg, 10);
    Controller.rebuildGrid(&game);
    try testing.expect(Controller.navigateTo(&game, mover, goal) == .accepted);
    game.removeComponent(cfg, nav.NavGrid);
    Controller.rebuildGrid(&game);
    try testing.expect(Controller.moveTo(&game, mover, .{ .x = 100, .y = 5 }) == .accepted);
    try testing.expectEqual(nav.Reason.grid_not_built, Controller.navigateTo(&game, mover, goal).rejected);
    try testing.expect(!Controller.isNavigating(&game, mover));
    try testing.expect(!game.hasComponent(mover, nav.Navigating));
    Controller.advance(&game, 1);
    try testing.expectEqual(@as(f32, 5), game.getPosition(mover).x);
}

test "a malformed scene grid still allows direct orders and can be repaired" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    var receiver: Receiver = .{};
    var hooks: Hooks = .{ .receivers = .{&receiver} };
    game.setHooks(&hooks);
    const cfg = game.createEntity();
    game.addComponent(cfg, nav.NavGrid{ .cols = 5, .rows = 0, .cell = 10 });
    const mover = addAt(&game, 5, 5);
    const goal: nav.Position = .{ .x = 45, .y = 5 };
    try Controller.setup(&game);
    defer Controller.deinit(&game);
    try testing.expectEqual(nav.Reason.invalid_grid, Controller.navigateTo(&game, mover, goal).rejected);
    const near: nav.Position = .{ .x = 8, .y = 5 };
    try testing.expect(Controller.moveTo(&game, mover, near) == .redundant);
    game.dispatchEvents();
    try testing.expectEqual(near.x, receiver.last.?.destination.?.direct.x);

    game.setField(nav.NavGrid, .rows, cfg, 1);
    Controller.rebuildGrid(&game);
    try testing.expect(Controller.navigateTo(&game, mover, goal) == .accepted);
    try testing.expectEqual(nav.Reason.graph_not_built, Controller.navigate(&game, mover, goal, @src()).deferred);
    try testing.expect(!Controller.isNavigating(&game, mover));

    game.setField(nav.NavGrid, .cols, cfg, 3);
    Controller.rebuildGrid(&game);
    game.dispatchEvents();
    try testing.expectEqual(@as(u32, 4), receiver.last_change.?.max_col);
    try testing.expect(Controller.isBlocked(&game, goal));
}

test "nearestAdjacent picks by walking cost, skips the unreachable and matches gridWalkCost" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    var receiver: Receiver = .{};
    var hooks: Hooks = .{ .receivers = .{&receiver} };
    game.setHooks(&hooks);
    // 9 x 5 cells of 10 px. The mover stands at the left; a wall with one gap
    // at the top row stands between it and the right half.
    //
    //   . . . . . . . . .      m = mover      (cell 1,2)
    //   . . . # . . . . .      A = `across`   (cell 5,2): 4 cells away in a
    //   . m . # . A . . .                     straight line, but past the wall
    //   . . . # . . . . .      B = `beside`   (cell 1,4): on the mover's side
    //   . B . # . . . . S      S = `sealed`   (cell 8,4): walled in, no free edge
    addGrid(&game, 9, 5);
    const mover = addAt(&game, 15, 25);
    const wall = addAt(&game, 35, 30);
    game.addComponent(wall, nav.NavObstacle{ .width = 8, .height = 38 });
    const across = addAt(&game, 55, 25);
    game.addComponent(across, nav.NavObstacle{ .width = 8, .height = 8 });
    const beside = addAt(&game, 15, 45);
    game.addComponent(beside, nav.NavObstacle{ .width = 8, .height = 8 });
    const sealed = addAt(&game, 85, 45);
    game.addComponent(sealed, nav.NavObstacle{ .width = 8, .height = 8 });
    for ([_][2]f32{ .{ 75, 45 }, .{ 85, 35 }, .{ 75, 35 } }) |p| {
        game.addComponent(addAt(&game, p[0], p[1]), nav.NavObstacle{ .width = 8, .height = 8 });
    }
    try Controller.setup(&game);
    defer Controller.deinit(&game);

    // `beside` is one step away. `across` is close as the crow flies but
    // behind the wall. The order of the list does not decide it.
    const first = Controller.nearestAdjacent(&game, mover, &[_]u32{ across, sealed, beside }).?;
    try testing.expectEqual(@as(u64, beside), first.target);
    // One axial step to the cell above it, at the default cell cost of 10.
    try testing.expectEqual(@as(u64, 100), first.cost);

    // Without `beside`, the walk goes through the gap to `across`. It ends
    // at the cheapest of that target's edge cells, the one above it, which
    // comes first on the way down from the gap; the cell on the wall's side
    // is farther. The cost is what gridWalkCost gives for that cell.
    const second = Controller.nearestAdjacent(&game, mover, &[_]u32{ sealed, across }).?;
    try testing.expectEqual(@as(u64, across), second.target);
    const above = Controller.gridWalkCost(&game, mover, .{ .x = 55, .y = 15 }).?;
    const wall_side = Controller.gridWalkCost(&game, mover, .{ .x = 45, .y = 25 }).?;
    try testing.expectEqual(above, second.cost);
    try testing.expect(above < wall_side);
    try testing.expect(second.cost > 300); // far more than the 3 cells a straight line would be

    // Nothing reachable, and nothing asked for.
    try testing.expect(Controller.nearestAdjacent(&game, mover, &[_]u32{sealed}) == null);
    try testing.expect(Controller.nearestAdjacent(&game, mover, &[_]u32{}) == null);
    // The answer is good for navigateAdjacent.
    try testing.expect(Controller.navigateAdjacent(&game, mover, @as(u32, @intCast(second.target))) == .accepted);
}
