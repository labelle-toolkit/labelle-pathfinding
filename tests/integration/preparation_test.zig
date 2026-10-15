const std = @import("std");
const testing = std.testing;
const engine = @import("engine");
const pf = @import("pathfinder");
const Game = engine.game_mod.Game;
const Entity = Game.EntityType;
const C = pf.Controller;
const CMN = pf.ClosestMovementNode;
const Participant = struct { value: u8 = 0 };

fn node(game: *Game, x: f32) Entity {
    const e = game.createEntity();
    game.addComponent(e, pf.MovementNode{});
    game.setPosition(e, .{ .x = x, .y = 0 });
    return e;
}
fn item(game: *Game, x: f32) Entity {
    const e = game.createEntity();
    game.addComponent(e, Participant{});
    game.setPosition(e, .{ .x = x, .y = 0 });
    return e;
}
fn stage(game: *Game, budget: usize) !pf.controller.PreparationStats {
    var view = game.active_world.ecs_backend.view(.{Participant}, .{});
    defer view.deinit();
    return try C.prepareEndpointBatch(game, &view, budget);
}
fn run(game: *Game, budget: usize) !pf.controller.PreparationStats {
    _ = try stage(game, budget);
    return C.publishEndpointBatch(game);
}
fn setup(game: *Game) !void {
    try C.setup(game);
    C.enableEndpointPreparation(game);
    C.advance(game, 0);
}

test "CMNs publish only at the barrier; bounded batches rotate past newly stale participants" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    const n = node(&game, 0);
    game.addComponent(n, Participant{}); // graph nodes must never get self-CMNs
    const a = item(&game, 1);
    const b = item(&game, 2);
    const c = item(&game, 3);
    try setup(&game);
    defer C.deinit(&game);
    const first = try stage(&game, 1);
    try testing.expectEqual(@as(usize, 1), first.selected);
    try testing.expect(!game.hasComponent(a, CMN));
    try testing.expect(!game.hasComponent(b, CMN));
    try testing.expectEqual(@as(usize, 1), C.publishEndpointBatch(&game).published);
    try testing.expectEqual(@as(u32, 0), game.getComponent(a, CMN).?.node_id);
    game.setPosition(a, .{ .x = 10 });
    _ = try run(&game, 1);
    try testing.expect(game.hasComponent(b, CMN));
    _ = try run(&game, 1);
    try testing.expect(game.hasComponent(c, CMN));
    try testing.expect(!game.hasComponent(n, CMN));
    _ = try run(&game, 1);
    try testing.expectEqual(game.positionRevision(a).?, game.getComponent(a, CMN).?.stamp.position_revision);
}

test "ancestor movement between compute and publication discards the old result" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    _ = node(&game, 0);
    const parent = game.createEntity();
    const e = item(&game, 1);
    game.setParent(e, parent, .{});
    try setup(&game);
    defer C.deinit(&game);
    _ = try stage(&game, 2);
    try testing.expectError(error.PreparationInProgress, stage(&game, 2));
    game.setPosition(parent, .{ .x = 10 });
    const stale = C.publishEndpointBatch(&game);
    try testing.expectEqual(@as(usize, 1), stale.discarded);
    try testing.expect(!game.hasComponent(e, CMN));
    try testing.expectEqual(@as(usize, 1), (try run(&game, 2)).published);
}

test "off-graph completion is skipped until the position changes" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    _ = node(&game, 0);
    const e = item(&game, 10000);
    try setup(&game);
    defer C.deinit(&game);
    try testing.expectEqual(@as(usize, 1), (try run(&game, 2)).off_graph);
    try testing.expectEqual(CMN.Status.off_graph, game.getComponent(e, CMN).?.status);
    try testing.expectEqual(@as(usize, 0), (try run(&game, 2)).selected);
    game.setPosition(e, .{ .x = 2 });
    try testing.expectEqual(@as(usize, 1), (try run(&game, 2)).published);
    try testing.expectEqual(CMN.Status.ready, game.getComponent(e, CMN).?.status);
}

test "node movement and link changes reject staging and rebuild on advance with unchanged node count" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    const n = node(&game, 0);
    _ = node(&game, 100);
    const e = item(&game, 1);
    try setup(&game);
    defer C.deinit(&game);
    _ = try stage(&game, 2);
    game.setPosition(n, .{ .x = 10 });
    try testing.expect(!C.publishEndpointBatch(&game).graph_ready);
    try testing.expect(!game.hasComponent(e, CMN));
    const epoch = C.graphEpoch(&game);
    C.advance(&game, 0);
    try testing.expect(C.graphEpoch(&game) > epoch);
    try testing.expectEqual(@as(usize, 1), (try run(&game, 2)).published);
    game.setComponent(n, pf.MovementLink{ .dx = 90 });
    try testing.expect(!(try stage(&game, 2)).graph_ready);
    C.advance(&game, 0);
    try testing.expect((try run(&game, 2)).graph_ready);
}

test "destroyed endpoints never receive a staged result" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    _ = node(&game, 0);
    const e = item(&game, 1);
    try setup(&game);
    defer C.deinit(&game);
    _ = try stage(&game, 2);
    game.destroyEntity(e);
    const replacement = item(&game, 2);
    try testing.expectEqual(@as(usize, 1), C.publishEndpointBatch(&game).discarded);
    try testing.expect(!game.hasComponent(replacement, CMN));
    try testing.expectEqual(@as(usize, 1), (try run(&game, 2)).published);
}

test "no graph and zero budget remain normal empty preparation outcomes" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    const e = item(&game, 1);
    try setup(&game);
    defer C.deinit(&game);
    try testing.expect(!(try run(&game, 2)).graph_ready);
    _ = node(&game, 0);
    C.advance(&game, 0);
    try testing.expectEqual(@as(usize, 0), (try run(&game, 0)).selected);
    try testing.expect(!game.hasComponent(e, CMN));
    try testing.expectEqual(@as(usize, 1), (try run(&game, 2)).published);
}

test "rebuild retains the old debugging record but legacy targetPosition resolves again" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    const a = node(&game, 0);
    const b = node(&game, 70);
    const e = item(&game, 1);
    try setup(&game);
    defer C.deinit(&game);
    _ = try run(&game, 1);
    const old = game.getComponent(e, CMN).?.*;
    game.setPosition(a, .{ .x = 200 });
    C.advance(&game, 0);
    const stale = game.getComponent(e, CMN).?.*;
    try testing.expectEqual(CMN.Status.pending, stale.status);
    try testing.expectEqual(old.node_entity, stale.node_entity);
    try testing.expectEqualDeep(old.last_ready_stamp, stale.last_ready_stamp);
    try testing.expectEqualDeep(game.getWorldPosition(b), C.targetPosition(&game, e));
}

test "graph replacement between compute and publication discards the old batch and preserves rotation" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    const n = node(&game, 0);
    const a = item(&game, 1);
    const b = item(&game, 2);
    try setup(&game);
    defer C.deinit(&game);
    _ = try stage(&game, 1);
    game.setPosition(n, .{ .x = 2 });
    C.advance(&game, 0);
    try testing.expectEqual(@as(usize, 1), C.publishEndpointBatch(&game).discarded);
    _ = try run(&game, 1);
    try testing.expect(!game.hasComponent(a, CMN));
    try testing.expect(game.hasComponent(b, CMN));
}

test "batch allocation failure cannot publish CMNs or advance the cursor" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    _ = node(&game, 0);
    const e = item(&game, 1);
    try setup(&game);
    defer C.deinit(&game);
    const state = C.getState(&game).?;
    var bytes: [0]u8 = .{};
    var allocator = std.heap.FixedBufferAllocator.init(&bytes);
    state.allocator = allocator.allocator();
    defer state.allocator = testing.allocator;
    try testing.expectError(error.OutOfMemory, stage(&game, 1));
    try testing.expectEqual(@as(?u64, null), state.preparation_batch.cursor);
    try testing.expectEqual(@as(usize, 0), C.publishEndpointBatch(&game).published);
    try testing.expect(!game.hasComponent(e, CMN));
}

test "controller replacement starts a fresh world stamp with no staged results" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    _ = node(&game, 0);
    const e = item(&game, 1);
    try setup(&game);
    defer C.deinit(&game);
    _ = try run(&game, 1);
    const old_world = game.getComponent(e, CMN).?.stamp.world_revision;
    game.setPosition(e, .{ .x = 2 });
    _ = try stage(&game, 1);
    try C.setup(&game); // replaces the state and destroys outstanding snapshots
    C.enableEndpointPreparation(&game);
    C.advance(&game, 0);
    try testing.expectEqual(@as(usize, 0), C.publishEndpointBatch(&game).published);
    _ = try run(&game, 1);
    try testing.expect(game.getComponent(e, CMN).?.stamp.world_revision != old_world);
}

test "snapshot allocation failure and explicit cancellation leave the turn unconsumed" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    _ = node(&game, 0);
    const a = item(&game, 1);
    const b = item(&game, 2);
    try setup(&game);
    defer C.deinit(&game);
    const state = C.getState(&game).?;
    try state.preparation_batch.begin(testing.allocator, 1);
    var bytes: [0]u8 = .{};
    var allocator = std.heap.FixedBufferAllocator.init(&bytes);
    {
        state.allocator = allocator.allocator();
        defer state.allocator = testing.allocator;
        try testing.expectError(error.OutOfMemory, stage(&game, 1));
    }
    try testing.expectEqual(@as(?u64, null), state.preparation_batch.cursor);
    const computed = try stage(&game, 1);
    try testing.expectEqual(@as(usize, 1), computed.nearest_searches);
    C.cancelEndpointBatch(&game);
    try testing.expectEqual(@as(usize, 0), C.publishEndpointBatch(&game).published);
    try testing.expect(!game.hasComponent(a, CMN));
    _ = try run(&game, 1);
    try testing.expect(game.hasComponent(a, CMN));
    try testing.expect(!game.hasComponent(b, CMN));
    try testing.expectEqual(@as(usize, 0), C.publishEndpointBatch(&game).published);
}

test "node removal and stair edits invalidate an already computed batch" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    const n = node(&game, 0);
    const e = item(&game, 1);
    try setup(&game);
    defer C.deinit(&game);
    _ = try stage(&game, 1);
    game.addComponent(n, pf.MovementStair{});
    try testing.expectEqual(@as(usize, 1), C.publishEndpointBatch(&game).discarded);
    C.advance(&game, 0);
    _ = try stage(&game, 1);
    C.removeNode(&game, game.getComponent(n, pf.MovementNode).?.node_id);
    try testing.expectEqual(@as(usize, 1), C.publishEndpointBatch(&game).discarded);
    try testing.expect(!game.hasComponent(e, CMN));
}

test "legacy targetPosition never treats off-graph debugging data as a ready node" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    _ = node(&game, 0);
    const e = item(&game, 1);
    try setup(&game);
    defer C.deinit(&game);
    _ = try run(&game, 1);
    const old = game.getComponent(e, CMN).?.*;
    game.setPosition(e, .{ .x = 10000 });
    _ = try run(&game, 1);
    const off_graph = game.getComponent(e, CMN).?.*;
    try testing.expectEqual(CMN.Status.off_graph, off_graph.status);
    try testing.expectEqual(old.node_entity, off_graph.node_entity);
    try testing.expectEqualDeep(game.getWorldPosition(e), C.targetPosition(&game, e));
}

test "prepared matching rejects stale endpoints and graph inputs without repairing them" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    const n = node(&game, 0);
    const n2 = node(&game, 50);
    const a = item(&game, 1);
    const b = item(&game, 51);
    try setup(&game);
    defer C.deinit(&game);
    try testing.expectEqual(null, C.preparedDistance(&game, a, b));
    _ = try run(&game, 8);
    try testing.expectEqual(@as(?f32, 50), C.preparedDistance(&game, a, b));
    try testing.expectEqual(@as(?f32, 50), C.preparedDistance(&game, n, n2));
    C.requestRepath(&game, a);
    try testing.expectEqual(CMN.Status.pending, game.getComponent(a, CMN).?.status);
    try testing.expectEqual(null, C.preparedDistance(&game, a, b));
    _ = try run(&game, 8);
    try testing.expectEqual(@as(?f32, 50), C.preparedDistance(&game, a, b));
    try testing.expect(!game.hasComponent(n, CMN));
    const old = game.getComponent(a, CMN).?.*;
    game.setPosition(a, .{ .x = 2 });
    try testing.expectEqual(null, C.preparedDistance(&game, a, b));
    try testing.expect(!C.endpointPreparationComplete(&game, a));
    try testing.expectEqualDeep(old, game.getComponent(a, CMN).?.*);
    _ = try run(&game, 8);
    try testing.expect(C.endpointPreparationComplete(&game, a));
    game.setPosition(n2, .{ .x = 60 });
    // Even a query involving only the unchanged node must reject the graph.
    try testing.expectEqual(null, C.preparedDistance(&game, n, n));
    C.advance(&game, 0);
    _ = try run(&game, 8);
    try testing.expectEqual(@as(?f32, 60), C.preparedDistance(&game, a, b));
    game.addComponent(n, pf.MovementStair{});
    try testing.expectEqual(null, C.preparedDistance(&game, a, b));
    C.advance(&game, 0);
    _ = try run(&game, 8);
    _ = node(&game, 75);
    try testing.expectEqual(null, C.preparedDistance(&game, a, b));
}

test "off-graph is complete but never a match; missing controller never falls back" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    const a = item(&game, 0);
    const b = item(&game, 10000);
    try testing.expectEqual(null, C.preparedDistance(&game, a, a));
    _ = node(&game, 0);
    try setup(&game);
    defer C.deinit(&game);
    _ = try run(&game, 8);
    try testing.expect(C.endpointPreparationComplete(&game, b));
    try testing.expectEqual(null, C.preparedDistance(&game, a, b));
    try testing.expectEqual(null, C.preparedDistance(&game, b, b));
}

test "known docking placement validates world geometry and is invalidated by ancestry" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    const dock = node(&game, 0);
    const other = node(&game, 500);
    const parent = game.createEntity();
    const bandit = item(&game, 1);
    game.setParent(bandit, parent, .{});
    try testing.expect(!try C.publishKnownEndpoint(&game, bandit, dock));
    try setup(&game);
    defer C.deinit(&game);
    _ = try run(&game, 8);
    try testing.expect(try C.publishKnownEndpoint(&game, bandit, dock));
    try testing.expectEqual(@as(?f32, 0), C.preparedDistance(&game, bandit, dock));
    try testing.expectEqual(null, C.preparedDistance(&game, bandit, other));
    try testing.expect(!try C.publishKnownEndpoint(&game, bandit, other));
    try testing.expect(!try C.publishKnownEndpoint(&game, dock, dock));
    game.setPosition(parent, .{ .x = 5 });
    try testing.expectEqual(null, C.preparedDistance(&game, bandit, dock));
    try testing.expect(try C.publishKnownEndpoint(&game, bandit, dock));
    game.setPosition(parent, .{ .y = -10 }); // anchor is above the allowed Y filter
    try testing.expect(!try C.publishKnownEndpoint(&game, bandit, dock));
    try testing.expectEqual(null, C.preparedDistance(&game, bandit, dock));
    game.setPosition(parent, .{ .x = 1000 });
    try testing.expect(!try C.publishKnownEndpoint(&game, bandit, dock));
}

test "small moves reuse only during preparation and preserve the original region" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    const n = node(&game, 0);
    _ = node(&game, 50);
    const e = item(&game, 1);
    try setup(&game);
    defer C.deinit(&game);
    _ = try run(&game, 1);
    const region = game.getComponent(e, CMN).?.reuse;
    for (2..10) |x| {
        game.setPosition(e, .{ .x = @floatFromInt(x) });
        try testing.expectEqual(null, C.preparedDistance(&game, e, n));
        const stats = try stage(&game, 1);
        try testing.expectEqual(@as(usize, 1), stats.reused_endpoints);
        try testing.expectEqual(@as(usize, 0), stats.nearest_searches);
        try testing.expectEqual(null, C.preparedDistance(&game, e, n));
        _ = C.publishEndpointBatch(&game);
        try testing.expectEqual(@as(?f32, 0), C.preparedDistance(&game, e, n));
        try testing.expectEqualDeep(region, game.getComponent(e, CMN).?.reuse);
    }
    game.setPosition(e, .{ .x = 30 });
    try testing.expectEqual(@as(usize, 1), (try stage(&game, 1)).nearest_searches);
    _ = C.publishEndpointBatch(&game);
    try testing.expectEqual(@as(?f32, 50), C.preparedDistance(&game, e, n));
}

test "reuse agrees with exhaustive nearest selection across ties Y boundaries and teleports" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    _ = node(&game, 0);
    _ = node(&game, 50);
    const upper = node(&game, 25);
    game.setPosition(upper, .{ .x = 25, .y = 10 });
    _ = node(&game, 50); // duplicate: retain first-node tie order
    const e = item(&game, 1);
    try setup(&game);
    defer C.deinit(&game);
    var reused: usize = 0;
    for (0..600) |i| {
        const x: f32 = @as(f32, @floatFromInt(i % 151)) - 40;
        const y: f32 = switch ((i / 151) % 4) {
            0 => 0,
            1 => 4.99999,
            2 => 5,
            else => 5.00001,
        };
        game.setPosition(e, .{ .x = x, .y = y });
        const stats = try run(&game, 1);
        reused += stats.reused_endpoints;
        const expected = pf.controller.findNearestNodeInState(C.getState(&game).?, x, y);
        const cmn = game.getComponent(e, CMN).?;
        if (expected) |id| {
            try testing.expectEqual(CMN.Status.ready, cmn.status);
            try testing.expectEqual(id, cmn.node_id);
        } else try testing.expectEqual(CMN.Status.off_graph, cmn.status);
    }
    try testing.expect(reused > 0);
    game.setPosition(e, .{ .x = 10000 });
    try testing.expectEqual(@as(usize, 1), (try run(&game, 1)).off_graph);
    game.setPosition(e, .{ .x = 1 });
    try testing.expectEqual(@as(usize, 1), (try run(&game, 1)).nearest_searches);
}

test "known placements and changed graphs cannot reuse a nearest certificate" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    const n = node(&game, 0);
    const e = item(&game, 1);
    try setup(&game);
    defer C.deinit(&game);
    _ = try run(&game, 1);
    try testing.expect(try C.publishKnownEndpoint(&game, e, n));
    game.setPosition(e, .{ .x = 2 });
    try testing.expectEqual(@as(usize, 1), (try run(&game, 1)).nearest_searches);
    game.setPosition(n, .{ .x = 3 });
    C.advance(&game, 0);
    try testing.expectEqual(@as(usize, 1), (try run(&game, 1)).nearest_searches);
    game.setPosition(e, .{ .x = 4 });
    try testing.expectEqual(@as(usize, 1), (try stage(&game, 1)).reused_endpoints);
    game.setPosition(e, .{ .x = 5 });
    try testing.expectEqual(@as(usize, 1), C.publishEndpointBatch(&game).discarded);
    try testing.expectEqual(null, C.preparedDistance(&game, e, n));
}

fn domainRun(game: *Game, budget: usize) !pf.controller.PreparationStats {
    _ = try C.prepareEndpointDomains(game, .{Participant}, budget);
    return C.publishEndpointBatch(game);
}

test "pending-only domains drain and idle frames visit no participants" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    const n = node(&game, 0);
    const parent = game.createEntity();
    const a = item(&game, 1);
    const b = item(&game, 2);
    game.setParent(a, parent, .{});
    try setup(&game);
    defer C.deinit(&game);
    const first = try domainRun(&game, 1);
    try testing.expectEqual(@as(usize, 2), first.domain_discovered);
    try testing.expectEqual(@as(usize, 2), first.discovered);
    try testing.expectEqual(@as(usize, 1), (try domainRun(&game, 1)).discovered);
    for (0..5) |_| {
        const idle = try domainRun(&game, 1);
        try testing.expectEqual(@as(usize, 0), idle.domain_discovered);
        try testing.expectEqual(@as(usize, 0), idle.discovered);
        try testing.expectEqual(@as(usize, 0), idle.nearest_searches);
    }
    game.setPosition(parent, .{ .x = 3 });
    try testing.expectEqual(null, C.preparedDistance(&game, a, n));
    const moved = try C.prepareEndpointDomains(&game, .{Participant}, 1);
    try testing.expectEqual(@as(usize, 0), moved.domain_discovered);
    try testing.expectEqual(@as(usize, 1), moved.discovered);
    try testing.expectEqual(null, C.preparedDistance(&game, a, n));
    _ = C.publishEndpointBatch(&game);
    try testing.expectEqual(@as(?f32, 0), C.preparedDistance(&game, a, b));
    game.setComponent(a, Participant{ .value = 3 });
    try testing.expectEqual(@as(usize, 0), (try domainRun(&game, 1)).domain_discovered);
}

test "pending domains discover additions and component removal without count heuristics" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    _ = node(&game, 0);
    const a = item(&game, 1);
    const b = game.createEntity();
    game.setPosition(b, .{ .x = 2 });
    try setup(&game);
    defer C.deinit(&game);
    _ = try domainRun(&game, 4);
    game.removeComponent(a, Participant);
    game.addComponent(b, Participant{}); // same participant count, different identity
    game.setPosition(a, .{ .x = 4 });
    const changed = try domainRun(&game, 4);
    try testing.expectEqual(@as(usize, 1), changed.domain_discovered);
    try testing.expectEqual(@as(usize, 1), changed.published);
    try testing.expect(C.endpointPreparationComplete(&game, b));
    game.setPosition(a, .{ .x = 5 });
    try testing.expectEqual(@as(usize, 0), (try domainRun(&game, 4)).discovered);
    game.active_world.ecs_backend.addComponent(a, Participant{});
    game.invalidateComponentMembership(Participant);
    try testing.expectEqual(@as(usize, 1), (try domainRun(&game, 4)).published);
    game.destroyEntity(b);
    try testing.expectEqual(@as(usize, 0), (try domainRun(&game, 4)).discovered);
}

test "pending work survives cancellation stale publication off graph and repath" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    _ = node(&game, 0);
    const a = item(&game, 1);
    const b = item(&game, 10000);
    try setup(&game);
    defer C.deinit(&game);
    _ = try C.prepareEndpointDomains(&game, .{Participant}, 1);
    C.cancelEndpointBatch(&game);
    try testing.expectEqual(@as(usize, 1), (try domainRun(&game, 1)).published);
    _ = try C.prepareEndpointDomains(&game, .{Participant}, 1);
    game.setPosition(b, .{ .x = 20000 });
    try testing.expectEqual(@as(usize, 1), C.publishEndpointBatch(&game).discarded);
    try testing.expectEqual(@as(usize, 1), (try domainRun(&game, 1)).off_graph);
    try testing.expectEqual(@as(usize, 0), (try domainRun(&game, 1)).discovered);
    C.requestRepath(&game, a);
    try testing.expectEqual(@as(usize, 1), (try domainRun(&game, 1)).published);
    game.setPosition(b, .{ .x = 2 });
    try testing.expectEqual(@as(usize, 1), (try domainRun(&game, 1)).published);
}

test "graph changes and node role changes requeue endpoints; moving entities cannot starve others" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    const n = node(&game, 0);
    const a = item(&game, 1);
    const b = item(&game, 2);
    const c = item(&game, 3);
    try setup(&game);
    defer C.deinit(&game);
    _ = try domainRun(&game, 1);
    game.setPosition(a, .{ .x = 4 });
    _ = try domainRun(&game, 1);
    try testing.expect(C.endpointPreparationComplete(&game, b));
    game.setPosition(a, .{ .x = 5 });
    _ = try domainRun(&game, 1);
    try testing.expect(C.endpointPreparationComplete(&game, c));
    _ = try domainRun(&game, 4);
    game.setPosition(n, .{ .x = 10 });
    C.advance(&game, 0);
    const rebuilt = try domainRun(&game, 4);
    try testing.expectEqual(@as(usize, 0), rebuilt.domain_discovered);
    try testing.expectEqual(@as(usize, 3), rebuilt.published);
    game.addComponent(a, pf.MovementNode{});
    C.advance(&game, 0);
    _ = try domainRun(&game, 4);
    game.removeComponent(a, pf.MovementNode);
    C.advance(&game, 0);
    _ = try domainRun(&game, 4);
    try testing.expect(C.endpointPreparationComplete(&game, a));
}

test "pending discovery retries after allocation failure and controller replacement" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    _ = node(&game, 0);
    const e = item(&game, 1);
    try setup(&game);
    defer C.deinit(&game);
    const state = C.getState(&game).?;
    var bytes: [0]u8 = .{};
    var allocator = std.heap.FixedBufferAllocator.init(&bytes);
    {
        state.allocator = allocator.allocator();
        defer state.allocator = testing.allocator;
        try testing.expectError(error.OutOfMemory, C.prepareEndpointDomains(&game, .{Participant}, 1));
    }
    try testing.expect(!C.endpointPreparationComplete(&game, e));
    try testing.expectEqual(@as(usize, 1), (try domainRun(&game, 1)).published);
    const old_world = game.getComponent(e, CMN).?.stamp.world_revision;
    try C.setup(&game);
    C.enableEndpointPreparation(&game);
    C.advance(&game, 0);
    try testing.expectEqual(@as(usize, 1), (try domainRun(&game, 1)).published);
    try testing.expect(game.getComponent(e, CMN).?.stamp.world_revision != old_world);
    game.removeComponent(e, CMN);
    try testing.expectEqual(@as(usize, 1), (try domainRun(&game, 1)).published);
}

test "pending and full-view preparation publish identical frame outcomes" {
    var reference = Game.init(testing.allocator);
    defer reference.deinit();
    var queued = Game.init(testing.allocator);
    defer queued.deinit();
    const rn = node(&reference, 0);
    const qn = node(&queued, 0);
    _ = node(&reference, 50);
    _ = node(&queued, 50);
    var re: [6]Entity = undefined;
    var qe: [6]Entity = undefined;
    for (0..5) |i| {
        re[i] = item(&reference, @floatFromInt(i * 10));
        qe[i] = item(&queued, @floatFromInt(i * 10));
    }
    try setup(&reference);
    defer C.deinit(&reference);
    try setup(&queued);
    defer C.deinit(&queued);
    C.setPreparationWorker(&queued, true);
    var count: usize = 5;
    for (0..60) |frame| {
        if (frame == 10) {
            re[5] = item(&reference, 10000);
            qe[5] = item(&queued, 10000);
            count = 6;
        }
        if (frame == 20) {
            reference.removeComponent(re[2], Participant);
            queued.removeComponent(qe[2], Participant);
        }
        if (frame == 30) {
            reference.addComponent(re[2], Participant{});
            queued.addComponent(qe[2], Participant{});
        }
        if (frame == 40) {
            reference.setPosition(rn, .{ .x = 5 });
            queued.setPosition(qn, .{ .x = 5 });
            C.advance(&reference, 0);
            C.advance(&queued, 0);
        }
        const i = frame % count;
        const pos = engine.Position{ .x = @floatFromInt(frame % 70) };
        reference.setPosition(re[i], pos);
        queued.setPosition(qe[i], pos);
        const full = try run(&reference, 2);
        const pending = try domainRun(&queued, 2);
        try testing.expectEqual(full.selected, pending.selected);
        try testing.expectEqual(full.published, pending.published);
        try testing.expectEqual(full.off_graph, pending.off_graph);
        for (0..count) |j| {
            try testing.expectEqual(C.preparedDistance(&reference, re[j], rn), C.preparedDistance(&queued, qe[j], qn));
        }
    }
}

test "prepared origin scans reject movement repath destruction and controller replacement" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    const n = node(&game, 0);
    const n2 = node(&game, 50);
    const a = item(&game, 1);
    const b = item(&game, 51);
    try setup(&game);
    defer C.deinit(&game);
    try testing.expectEqual(null, C.preparedDistancesFrom(&game, a));
    _ = try domainRun(&game, 8);
    var scan = C.preparedDistancesFrom(&game, a).?;
    try testing.expectEqual(C.preparedDistance(&game, a, b), scan.to(b));
    // A validated known placement can change the node without changing the stamp.
    try testing.expect(try C.publishKnownEndpoint(&game, a, n2));
    try testing.expectEqual(null, scan.to(b));
    scan = C.preparedDistancesFrom(&game, a).?;
    C.requestRepath(&game, a);
    try testing.expectEqual(null, scan.to(b));
    _ = try domainRun(&game, 8);
    scan = C.preparedDistancesFrom(&game, a).?;
    game.setPosition(a, .{ .x = 2 });
    try testing.expectEqual(null, scan.to(b));
    _ = try domainRun(&game, 8);
    scan = C.preparedDistancesFrom(&game, a).?;
    var direct = C.preparedDistancesFrom(&game, n).?;
    game.setPosition(n2, .{ .x = 60 });
    try testing.expectEqual(null, scan.to(b));
    try testing.expectEqual(null, direct.to(n));
    C.advance(&game, 0);
    _ = try domainRun(&game, 8);
    scan = C.preparedDistancesFrom(&game, a).?;
    try C.setup(&game);
    C.enableEndpointPreparation(&game);
    C.advance(&game, 0);
    _ = try domainRun(&game, 8);
    try testing.expectEqual(null, scan.to(b));
    scan = C.preparedDistancesFrom(&game, a).?;
    game.destroyEntity(a);
    try testing.expectEqual(null, scan.to(b));
}

test "worker batch joins all results and retains publication cancellation and stale checks" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    const n = node(&game, 0);
    const a = item(&game, 1);
    const b = item(&game, 2);
    const c = item(&game, 10000);
    try setup(&game);
    defer C.deinit(&game);
    C.setPreparationWorker(&game, true);
    const computed = try C.prepareEndpointDomains(&game, .{Participant}, 3);
    if (!@import("builtin").single_threaded) try testing.expect(computed.worker_executed);
    try testing.expectEqual(null, C.preparedDistance(&game, a, n));
    C.cancelEndpointBatch(&game);
    try testing.expect(!game.hasComponent(a, CMN));
    _ = try C.prepareEndpointDomains(&game, .{Participant}, 3);
    game.setPosition(b, .{ .x = 3 });
    const published = C.publishEndpointBatch(&game);
    try testing.expectEqual(@as(usize, 1), published.discarded);
    try testing.expectEqual(@as(usize, 1), published.off_graph);
    try testing.expectEqual(@as(?f32, 0), C.preparedDistance(&game, a, n));
    try testing.expectEqual(null, C.preparedDistance(&game, b, n));
    try testing.expect(C.endpointPreparationComplete(&game, c));
    _ = try domainRun(&game, 3);
    try testing.expectEqual(@as(?f32, 0), C.preparedDistance(&game, b, n));
}

test "legacy navigation target lookup preserves stale matching debug records" {
    var game = Game.init(testing.allocator);
    defer game.deinit();
    _ = node(&game, 0);
    _ = node(&game, 50);
    const a = item(&game, 1);
    try setup(&game);
    defer C.deinit(&game);
    _ = try domainRun(&game, 1);
    game.setPosition(a, .{ .x = 51 });
    const old = game.getComponent(a, CMN).?.*;
    _ = C.targetPosition(&game, a);
    try testing.expectEqualDeep(old, game.getComponent(a, CMN).?.*);
    try testing.expect(!C.endpointPreparationComplete(&game, a));
    _ = try domainRun(&game, 1);
    try testing.expect(C.endpointPreparationComplete(&game, a));
}
