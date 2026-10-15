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
