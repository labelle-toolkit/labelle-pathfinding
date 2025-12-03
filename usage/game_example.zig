//! Game Integration Example
//!
//! Shows how PathfindingEngine integrates with a typical game loop,
//! including callbacks, spatial queries for combat, and multiple entities.

const std = @import("std");
const pathfinding = @import("pathfinding");

const print = std.debug.print;

// ===== Game Types =====

const EntityId = u64;

const EntityType = enum {
    player,
    enemy,
    npc,
};

const GameState = struct {
    entities: std.AutoHashMap(EntityId, EntityType),
    score: u32 = 0,
    events: std.ArrayListUnmanaged([]const u8),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) GameState {
        return .{
            .entities = std.AutoHashMap(EntityId, EntityType).init(allocator),
            .events = .{},
            .allocator = allocator,
        };
    }

    fn deinit(self: *GameState) void {
        self.entities.deinit();
        self.events.deinit(self.allocator);
    }

    fn addEntity(self: *GameState, id: EntityId, entity_type: EntityType) !void {
        try self.entities.put(id, entity_type);
    }

    fn logEvent(self: *GameState, event: []const u8) void {
        self.events.append(self.allocator, event) catch {};
    }
};

// ===== Pathfinding Configuration =====

const Config = struct {
    pub const Entity = EntityId;
    pub const Context = *GameState;
};

const Pathfinding = pathfinding.PathfindingEngine(Config);

// ===== Callbacks =====

fn onNodeReached(game: *GameState, entity: EntityId, node: pathfinding.NodeId) void {
    const entity_type = game.entities.get(entity) orelse return;
    const type_name = switch (entity_type) {
        .player => "Player",
        .enemy => "Enemy",
        .npc => "NPC",
    };
    _ = node;
    _ = type_name;
    // In a real game, you might trigger events here
}

fn onPathCompleted(game: *GameState, entity: EntityId, node: pathfinding.NodeId) void {
    _ = node;
    const entity_type = game.entities.get(entity) orelse return;

    switch (entity_type) {
        .player => {
            game.score += 10;
            game.logEvent("Player reached destination (+10 points)");
        },
        .enemy => {
            game.logEvent("Enemy reached patrol point");
        },
        .npc => {
            game.logEvent("NPC arrived");
        },
    }
}

fn onPathBlocked(game: *GameState, entity: EntityId, node: pathfinding.NodeId) void {
    _ = entity;
    _ = node;
    game.logEvent("Path blocked!");
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("\n=== Game Integration Example ===\n\n", .{});

    // Initialize game and pathfinding
    var game = GameState.init(allocator);
    defer game.deinit();

    var pf = Pathfinding.init(allocator);
    defer pf.deinit();

    // Set up callbacks
    pf.on_node_reached = onNodeReached;
    pf.on_path_completed = onPathCompleted;
    pf.on_path_blocked = onPathBlocked;

    // ===== Build the game world =====
    print("1. Building game world...\n\n", .{});

    // Create a simple dungeon layout:
    //
    //   [0]-----[1]-----[2]
    //    |       |       |
    //   [3]-----[4]-----[5]
    //    |       |       |
    //   [6]-----[7]-----[8]
    //
    //   Spawn    Chest   Exit

    const waypoints = [_]pathfinding.NodePoint{
        .{ .id = 0, .x = 0, .y = 0 }, // Spawn
        .{ .id = 1, .x = 100, .y = 0 },
        .{ .id = 2, .x = 200, .y = 0 },
        .{ .id = 3, .x = 0, .y = 100 },
        .{ .id = 4, .x = 100, .y = 100 }, // Chest
        .{ .id = 5, .x = 200, .y = 100 },
        .{ .id = 6, .x = 0, .y = 200 },
        .{ .id = 7, .x = 100, .y = 200 },
        .{ .id = 8, .x = 200, .y = 200 }, // Exit
    };

    try pf.addNodesFromPoints(&waypoints);
    try pf.connectNodes(.{ .omnidirectional = .{ .max_distance = 120, .max_connections = 4 } });
    try pf.rebuildPaths();

    print("   Created 9 waypoints in 3x3 grid\n", .{});
    print("   Waypoint 0 = Spawn, 4 = Chest, 8 = Exit\n\n", .{});

    // ===== Spawn entities =====
    print("2. Spawning entities...\n\n", .{});

    const player_id: EntityId = 1;
    const enemy1_id: EntityId = 2;
    const enemy2_id: EntityId = 3;

    try game.addEntity(player_id, .player);
    try game.addEntity(enemy1_id, .enemy);
    try game.addEntity(enemy2_id, .enemy);

    try pf.registerEntity(player_id, 0, 0, 150.0); // Player at spawn, fast
    try pf.registerEntity(enemy1_id, 200, 0, 80.0); // Enemy at top-right, slow
    try pf.registerEntity(enemy2_id, 200, 200, 80.0); // Enemy at exit, slow

    print("   Player spawned at (0, 0), speed=150\n", .{});
    print("   Enemy 1 spawned at (200, 0), speed=80\n", .{});
    print("   Enemy 2 spawned at (200, 200), speed=80\n\n", .{});

    // ===== Game scenario: Player goes to chest, then exit =====
    print("3. Game scenario: Player collects chest then exits...\n\n", .{});

    // Player goes to chest
    try pf.requestPath(player_id, 4);
    print("   Player moving to chest (node 4)...\n", .{});

    // Enemies patrol
    try pf.requestPath(enemy1_id, 6); // Top-right to bottom-left
    try pf.requestPath(enemy2_id, 0); // Exit to spawn

    // Run until player reaches chest
    const delta: f32 = 0.05;
    while (pf.isMoving(player_id)) {
        pf.tick(&game, delta);
    }

    print("   Player reached chest!\n", .{});

    // Player goes to exit
    try pf.requestPath(player_id, 8);
    print("   Player moving to exit (node 8)...\n", .{});

    while (pf.isMoving(player_id)) {
        pf.tick(&game, delta);
    }

    print("   Player reached exit!\n\n", .{});

    // ===== Spatial queries for combat =====
    print("4. Spatial queries (combat system)...\n\n", .{});

    const player_pos = pf.getPosition(player_id).?;
    print("   Player at ({d:.0}, {d:.0})\n", .{ player_pos.x, player_pos.y });

    // Find enemies within attack range
    const attack_range: f32 = 150.0;
    var nearby: [10]EntityId = undefined;
    const found = pf.getEntitiesInRadius(player_pos.x, player_pos.y, attack_range, &nearby);

    print("   Entities within {d:.0} units:\n", .{attack_range});
    for (found) |entity| {
        const pos = pf.getPosition(entity).?;
        const entity_type = game.entities.get(entity).?;
        const type_name = switch (entity_type) {
            .player => "Player",
            .enemy => "Enemy",
            .npc => "NPC",
        };
        print("   - {s} at ({d:.0}, {d:.0})\n", .{ type_name, pos.x, pos.y });
    }

    // ===== Final state =====
    print("\n5. Final game state...\n\n", .{});

    print("   Score: {d}\n", .{game.score});
    print("   Events:\n", .{});
    for (game.events.items) |event| {
        print("   - {s}\n", .{event});
    }

    print("\n=== Game Integration Example Complete ===\n\n", .{});
}
