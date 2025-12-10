//! Basic PathfindingEngine Usage Example
//!
//! This is the recommended starting point for using labelle-pathfinding.
//! Shows the most common use case: entities moving along waypoints in a game.

const std = @import("std");
const pathfinding = @import("pathfinding");

const print = std.debug.print;

// Your game context passed to callbacks
const Game = struct {
    name: []const u8,
};

// Configure the engine with your types
// Entity can be any integer type (u32, u64, etc.)
const Config = struct {
    pub const Entity = u64;
    pub const Context = *Game;
};

// Alias for convenience
const Entity = Config.Entity;
const Vec2 = pathfinding.Vec2;

const Engine = pathfinding.PathfindingEngine(Config);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("\n=== Basic PathfindingEngine Example ===\n\n", .{});

    var game = Game{ .name = "My Game" };
    var engine = try Engine.init(allocator);
    defer engine.deinit();

    // ===== Step 1: Create waypoints (nodes) =====
    print("1. Creating waypoints...\n", .{});

    // Simple path: Start -> Middle -> End
    //   [0] ---- [1] ---- [2]
    //   (0,0)   (100,0)  (200,0)

    try engine.addNode(0, 0, 0);
    try engine.addNode(1, 100, 0);
    try engine.addNode(2, 200, 0);
    print("   Created 3 waypoints in a line\n\n", .{});

    // ===== Step 2: Connect waypoints =====
    print("2. Connecting waypoints...\n", .{});

    try engine.connectNodes(.{
        .omnidirectional = .{
            .max_distance = 150,
            .max_connections = 4,
        },
    });
    try engine.rebuildPaths();
    print("   Waypoints connected and paths computed\n\n", .{});

    // ===== Step 3: Add an entity =====
    print("3. Registering entity...\n", .{});

    const player: Entity = 1;
    try engine.registerEntity(player, 0, 0, 100.0); // at (0,0), speed 100
    print("   Player registered at waypoint 0\n\n", .{});

    // ===== Step 4: Request a path =====
    print("4. Requesting path to waypoint 2...\n", .{});

    try engine.requestPath(player, 2);
    print("   Path requested\n\n", .{});

    // ===== Step 5: Game loop =====
    print("5. Running game loop...\n", .{});

    const delta: f32 = 0.1; // 100ms per tick
    while (engine.isMoving(player)) {
        engine.tick(&game, delta);

        const pos = engine.getPosition(player).?;
        print("   Player position: ({d:.0}, {d:.0})\n", .{ pos.x, pos.y });
    }

    print("\n   Player arrived at destination!\n", .{});

    // ===== Step 6: Query final position =====
    print("\n6. Final state:\n", .{});

    // getPosition returns Vec2 from zig-utils for ecosystem compatibility
    const final_pos: Vec2 = engine.getPosition(player).?;
    const current_node = engine.getCurrentNode(player).?;

    print("   Position: ({d:.0}, {d:.0})\n", .{ final_pos.x, final_pos.y });
    print("   Current waypoint: {d}\n", .{current_node});
    print("   Is moving: {}\n", .{engine.isMoving(player)});

    // Vec2 provides useful methods like distance calculation
    const start = Vec2{ .x = 0, .y = 0 };
    print("   Distance traveled: {d:.0}\n", .{start.distance(final_pos)});

    print("\n=== Basic Example Complete ===\n\n", .{});
}
