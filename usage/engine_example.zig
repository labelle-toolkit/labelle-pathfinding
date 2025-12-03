//! PathfindingEngine Usage Example
//!
//! Demonstrates using the self-contained PathfindingEngine that owns
//! entity positions internally. The game queries the engine for positions
//! rather than storing them in an ECS.

const std = @import("std");
const pathfinding = @import("pathfinding");

const print = std.debug.print;

// Game-specific types
const GameEntity = u64;

const Game = struct {
    score: u32 = 0,
    pathfinding_events: u32 = 0,
};

// Configure the pathfinding engine with game types
const Config = struct {
    pub const Entity = GameEntity;
    pub const Context = *Game;
};

const Engine = pathfinding.PathfindingEngine(Config);

// Callback handlers
fn onNodeReached(game: *Game, entity: GameEntity, node: pathfinding.NodeId) void {
    _ = entity;
    _ = node;
    game.pathfinding_events += 1;
}

fn onPathCompleted(game: *Game, entity: GameEntity, node: pathfinding.NodeId) void {
    _ = entity;
    _ = node;
    game.score += 10;
    game.pathfinding_events += 1;
    print("   Path completed! Score: {d}\n", .{game.score});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("\n=== PathfindingEngine Example ===\n\n", .{});

    // Initialize game state and pathfinding engine
    var game = Game{};
    var engine = Engine.init(allocator);
    defer engine.deinit();

    // Set up callbacks
    engine.on_node_reached = onNodeReached;
    engine.on_path_completed = onPathCompleted;

    // ===== 1. Build the node graph =====
    print("1. Building node graph...\n\n", .{});

    // Create a grid of waypoints (top-down game style)
    //   0 --- 1 --- 2
    //   |     |     |
    //   3 --- 4 --- 5
    //   |     |     |
    //   6 --- 7 --- 8

    try engine.addNode(0, 0, 0);
    try engine.addNode(1, 100, 0);
    try engine.addNode(2, 200, 0);
    try engine.addNode(3, 0, 100);
    try engine.addNode(4, 100, 100);
    try engine.addNode(5, 200, 100);
    try engine.addNode(6, 0, 200);
    try engine.addNode(7, 100, 200);
    try engine.addNode(8, 200, 200);

    print("   Created 9 nodes in a 3x3 grid\n", .{});

    // Connect nodes using omnidirectional mode
    try engine.connectNodes(.{ .omnidirectional = .{
        .max_distance = 120, // Connect nodes within 120 units
        .max_connections = 4, // Max 4 connections per node
    } });

    print("   Connected nodes (omnidirectional, max_distance=120)\n", .{});

    // Rebuild shortest paths
    try engine.rebuildPaths();
    print("   Rebuilt Floyd-Warshall shortest paths\n\n", .{});

    // ===== 2. Register entities =====
    print("2. Registering entities...\n\n", .{});

    const player_id: GameEntity = 1;
    const enemy_id: GameEntity = 2;

    // Register player at node 0 (top-left)
    try engine.registerEntity(player_id, 0, 0, 150.0); // speed: 150 units/sec
    print("   Player registered at (0, 0), speed=150\n", .{});

    // Register enemy at node 8 (bottom-right)
    try engine.registerEntity(enemy_id, 200, 200, 100.0); // speed: 100 units/sec
    print("   Enemy registered at (200, 200), speed=100\n\n", .{});

    // ===== 3. Request paths =====
    print("3. Requesting paths...\n\n", .{});

    // Player moves to bottom-right
    try engine.requestPath(player_id, 8);
    print("   Player requested path to node 8 (bottom-right)\n", .{});

    // Enemy moves to top-left
    try engine.requestPath(enemy_id, 0);
    print("   Enemy requested path to node 0 (top-left)\n\n", .{});

    // ===== 4. Game loop simulation =====
    print("4. Simulating game loop...\n\n", .{});

    const delta: f32 = 0.1; // 100ms per tick
    var tick: u32 = 0;

    while (engine.isMoving(player_id) or engine.isMoving(enemy_id)) {
        engine.tick(&game, delta);
        tick += 1;

        if (tick % 10 == 0) { // Print every 10 ticks (1 second)
            const player_pos = engine.getPosition(player_id).?;
            const enemy_pos = engine.getPosition(enemy_id).?;
            print("   Tick {d}: Player ({d:.0}, {d:.0}), Enemy ({d:.0}, {d:.0})\n", .{
                tick,
                player_pos.x,
                player_pos.y,
                enemy_pos.x,
                enemy_pos.y,
            });
        }

        if (tick > 200) break; // Safety limit
    }

    print("\n   Simulation complete after {d} ticks\n", .{tick});
    print("   Pathfinding events: {d}\n", .{game.pathfinding_events});
    print("   Final score: {d}\n\n", .{game.score});

    // ===== 5. Spatial queries =====
    print("5. Demonstrating spatial queries...\n\n", .{});

    // Find entities near the center
    var nearby: [10]GameEntity = undefined;
    const found = engine.getEntitiesInRadius(100, 100, 150, &nearby);

    print("   Entities within 150 units of center (100, 100):\n", .{});
    for (found) |entity| {
        const pos = engine.getPosition(entity).?;
        print("   - Entity {d} at ({d:.0}, {d:.0})\n", .{ entity, pos.x, pos.y });
    }

    // ===== 6. Query position from engine =====
    print("\n6. Querying entity positions (engine owns positions)...\n\n", .{});

    if (engine.getPositionFull(player_id)) |pos| {
        print("   Player full position:\n", .{});
        print("   - Coordinates: ({d:.0}, {d:.0})\n", .{ pos.x, pos.y });
        print("   - Current node: {d}\n", .{pos.current_node});
        print("   - Speed: {d}\n", .{pos.speed});
        print("   - Is moving: {}\n", .{engine.isMoving(player_id)});
    }

    print("\n=== PathfindingEngine Example Complete ===\n\n", .{});
}
