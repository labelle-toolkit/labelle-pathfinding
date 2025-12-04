//! Raylib Building Pathfinding Example
//!
//! A multi-floor building with multiple staircases.
//! Click on nodes to move entities between floors.
//!
//! Controls:
//! - Left Click: Set entity target
//! - 1-5: Select entity by number
//! - Space: Add new entity
//! - R: Reset all entities
//! - N: Toggle random wandering mode
//! - V: Increase speed
//! - S: Cycle stair mode (all -> single -> direction -> all)
//! - =: Add more entities
//! - -: Remove entities

const std = @import("std");
const pathfinding = @import("pathfinding");
const rl = @import("raylib");

const PathfindingEngine = pathfinding.PathfindingEngine;

const WINDOW_WIDTH = 1000;
const WINDOW_HEIGHT = 700;
const NODE_RADIUS = 14;
const ENTITY_RADIUS = 12;
const FLOOR_HEIGHT = 140;
const FLOOR_Y_OFFSET = 80;

const Config = struct {
    pub const Entity = u32;
    pub const Context = *Game;
    pub const log_level = pathfinding.LogLevel.none;
};

const Engine = PathfindingEngine(Config);

const Game = struct {
    engine: *Engine,
    allocator: std.mem.Allocator,
    next_entity_id: u32 = 0,
    selected_entity: ?u32 = null,
    message: [:0]const u8 = "Click a node to move the entity",
    message_timer: f32 = 0,
    floor_count: u32 = 5,
    nodes_per_floor: u32 = 8,
    random_mode: bool = false,
    speed_multiplier: f32 = 1.0,
    rand_state: u32 = 12345,
    stair_mode: pathfinding.StairMode = .all,
    stair_positions: []const u32 = &[_]u32{ 1, 4, 6 },

    fn nextRandom(self: *Game) u32 {
        // Simple LCG random
        self.rand_state = self.rand_state *% 1103515245 +% 12345;
        return (self.rand_state >> 16) & 0x7FFF;
    }

    fn randomNode(self: *Game) u32 {
        const total = self.floor_count * self.nodes_per_floor;
        return self.nextRandom() % total;
    }
};

// Color palette
const COLORS = struct {
    const bg = rl.Color.init(20, 20, 30, 255);
    const floor_bg = rl.Color.init(30, 35, 45, 255);
    const floor_border = rl.Color.init(50, 60, 80, 255);
    const node = rl.Color.init(60, 80, 120, 255);
    const node_outline = rl.Color.init(100, 130, 180, 255);
    const stair = rl.Color.init(255, 180, 50, 255);
    const stair_outline = rl.Color.init(255, 220, 100, 255);
    const stair_occupied = rl.Color.init(255, 100, 100, 255); // Red when occupied
    const stair_single = rl.Color.init(255, 150, 50, 255); // Orange for single mode
    const edge = rl.Color.init(40, 50, 70, 255);
    const stair_edge = rl.Color.init(200, 140, 40, 255);
    const entity = rl.Color.init(80, 200, 120, 255);
    const entity_selected = rl.Color.init(120, 255, 160, 255);
    const entity_waiting = rl.Color.init(200, 200, 80, 255); // Yellow when waiting
    const text = rl.Color.init(200, 200, 210, 255);
    const text_dim = rl.Color.init(100, 110, 130, 255);
    const panel = rl.Color.init(25, 30, 40, 240);
    const panel_border = rl.Color.init(60, 70, 100, 255);
    const title = rl.Color.init(100, 150, 255, 255);
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var engine = try Engine.init(allocator);
    defer engine.deinit();

    var game = Game{
        .engine = &engine,
        .allocator = allocator,
    };

    // Setup callbacks
    engine.on_path_completed = onPathCompleted;

    // Build the multi-floor building
    try setupBuilding(&engine, &game);

    // Add initial entities
    try addEntityAtNode(&game, 0); // Ground floor left
    try addEntityAtNode(&game, 7); // Ground floor right
    try addEntityAtNode(&game, 16); // Middle floor
    game.selected_entity = 0;

    // Initialize Raylib
    rl.initWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Labelle Pathfinding - Multi-Floor Building");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    while (!rl.windowShouldClose()) {
        const delta = rl.getFrameTime();

        handleInput(&game);
        engine.tick(&game, delta);
        updateMessage(&game, delta);

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(COLORS.bg);

        drawBuilding(&game);
        drawEntities(&game);
        drawUI(&game);
    }
}

fn setupBuilding(engine: *Engine, game: *Game) !void {
    const floors = game.floor_count;
    const nodes_per_floor = game.nodes_per_floor;
    const node_spacing: f32 = 100;
    const start_x: f32 = 100;

    var node_id: u32 = 0;

    // Create nodes for each floor
    for (0..floors) |floor_idx| {
        const floor: u32 = @intCast(floor_idx);
        const y: f32 = FLOOR_Y_OFFSET + @as(f32, @floatFromInt(floors - 1 - floor)) * FLOOR_HEIGHT;

        for (0..nodes_per_floor) |node_idx| {
            const idx: u32 = @intCast(node_idx);
            const x: f32 = start_x + @as(f32, @floatFromInt(idx)) * node_spacing;

            // Check if this is a stair position
            var is_stair = false;
            for (game.stair_positions) |stair_pos| {
                if (idx == stair_pos) {
                    is_stair = true;
                    break;
                }
            }

            if (is_stair) {
                try engine.addNodeWithStairMode(node_id, x, y, game.stair_mode);
            } else {
                try engine.addNode(node_id, x, y);
            }

            node_id += 1;
        }
    }

    // Set up waiting areas for single/direction stair modes
    if (game.stair_mode == .single or game.stair_mode == .direction) {
        // For each stair column, set waiting areas
        for (game.stair_positions) |stair_pos| {
            // For each floor's stair node
            for (0..floors) |floor_idx| {
                const stair_node: u32 = @intCast(floor_idx * nodes_per_floor + stair_pos);
                // Waiting spots are adjacent nodes on the same floor
                var waiting_spots: [2]pathfinding.NodeId = undefined;
                var spot_count: usize = 0;

                // Left neighbor
                if (stair_pos > 0) {
                    waiting_spots[spot_count] = @intCast(floor_idx * nodes_per_floor + stair_pos - 1);
                    spot_count += 1;
                }
                // Right neighbor
                if (stair_pos < nodes_per_floor - 1) {
                    waiting_spots[spot_count] = @intCast(floor_idx * nodes_per_floor + stair_pos + 1);
                    spot_count += 1;
                }

                if (spot_count > 0) {
                    try engine.setWaitingArea(stair_node, waiting_spots[0..spot_count]);
                }
            }
        }
    }

    // Connect using building mode
    try engine.connectNodes(.{
        .building = .{
            .horizontal_range = node_spacing + 20,
            .floor_height = FLOOR_HEIGHT + 20,
        },
    });
    try engine.rebuildPaths();
}

fn rebuildBuilding(game: *Game) !void {
    // Save entity positions
    const EntityState = struct {
        x: f32,
        y: f32,
        speed: f32,
    };
    var saved_entities: [64]EntityState = undefined;
    var entity_count: u32 = 0;

    for (0..game.next_entity_id) |i| {
        const entity: u32 = @intCast(i);
        if (game.engine.getPosition(entity)) |pos| {
            if (entity_count < 64) {
                saved_entities[entity_count] = .{
                    .x = pos.x,
                    .y = pos.y,
                    .speed = game.engine.getSpeed(entity) orelse 80.0,
                };
                entity_count += 1;
            }
        }
        game.engine.unregisterEntity(entity);
    }

    // Clear the engine graph
    game.engine.clearGraph();

    // Rebuild with new stair mode
    try setupBuilding(game.engine, game);

    // Restore entities
    game.next_entity_id = 0;
    for (0..entity_count) |i| {
        const state = saved_entities[i];
        try game.engine.registerEntity(game.next_entity_id, state.x, state.y, state.speed);
        game.next_entity_id += 1;
    }

    // Reset selected entity if needed
    if (game.selected_entity) |sel| {
        if (sel >= game.next_entity_id) {
            game.selected_entity = if (game.next_entity_id > 0) game.next_entity_id - 1 else null;
        }
    }
}

fn addEntityAtNode(game: *Game, node_id: u32) !void {
    if (game.engine.getNodePosition(node_id)) |pos| {
        const speed = 80.0 + @as(f32, @floatFromInt(game.next_entity_id)) * 15.0;
        try game.engine.registerEntity(game.next_entity_id, pos.x, pos.y, speed);
        game.next_entity_id += 1;
    }
}

fn handleInput(game: *Game) void {
    const mouse_pos = rl.getMousePosition();

    // Left click - set target
    if (rl.isMouseButtonPressed(.left)) {
        if (game.selected_entity) |entity| {
            if (findNearestNode(game.engine, mouse_pos.x, mouse_pos.y, 40)) |node_id| {
                game.engine.requestPath(entity, node_id) catch {
                    game.message = "No path to target!";
                    game.message_timer = 2.0;
                    return;
                };
                game.message = "Moving...";
                game.message_timer = 1.0;
            }
        }
    }

    // Number keys to select entities
    if (rl.isKeyPressed(.one)) selectEntity(game, 0);
    if (rl.isKeyPressed(.two)) selectEntity(game, 1);
    if (rl.isKeyPressed(.three)) selectEntity(game, 2);
    if (rl.isKeyPressed(.four)) selectEntity(game, 3);
    if (rl.isKeyPressed(.five)) selectEntity(game, 4);

    // Space - Add new entity at random node
    if (rl.isKeyPressed(.space)) {
        const total_nodes = game.floor_count * game.nodes_per_floor;
        const node_id: u32 = @intCast(@mod(game.next_entity_id * 13 + 5, total_nodes));
        addEntityAtNode(game, node_id) catch {};
        game.selected_entity = game.next_entity_id - 1;
        game.message = "New entity added";
        game.message_timer = 1.0;
    }

    // R - Reset all entities
    if (rl.isKeyPressed(.r)) {
        // Remove all entities
        for (0..game.next_entity_id) |i| {
            game.engine.unregisterEntity(@intCast(i));
        }
        game.next_entity_id = 0;
        game.random_mode = false;
        game.speed_multiplier = 1.0;

        // Add initial entities
        addEntityAtNode(game, 0) catch {};
        addEntityAtNode(game, 7) catch {};
        addEntityAtNode(game, 16) catch {};
        game.selected_entity = 0;
        game.message = "Entities reset";
        game.message_timer = 1.0;
    }

    // N - Toggle random wandering mode
    if (rl.isKeyPressed(.n)) {
        game.random_mode = !game.random_mode;
        if (game.random_mode) {
            // Send all entities to random nodes
            for (0..game.next_entity_id) |i| {
                const entity: u32 = @intCast(i);
                if (game.engine.getPosition(entity) != null) {
                    const target = game.randomNode();
                    game.engine.requestPath(entity, target) catch {};
                }
            }
            game.message = "Random mode ON";
        } else {
            game.message = "Random mode OFF";
        }
        game.message_timer = 1.5;
    }

    // V - Increase speed
    if (rl.isKeyPressed(.v)) {
        game.speed_multiplier += 0.5;
        if (game.speed_multiplier > 5.0) {
            game.speed_multiplier = 1.0;
        }

        // Update all entity speeds
        for (0..game.next_entity_id) |i| {
            const entity: u32 = @intCast(i);
            const base_speed = 80.0 + @as(f32, @floatFromInt(entity)) * 15.0;
            game.engine.setSpeed(entity, base_speed * game.speed_multiplier);
        }

        game.message = "Speed increased";
        game.message_timer = 1.0;
    }

    // = (equal) - Add more entities
    if (rl.isKeyPressed(.equal)) {
        const count_to_add: u32 = 5;
        for (0..count_to_add) |_| {
            const node_id = game.randomNode();
            addEntityAtNode(game, node_id) catch {};

            // If random mode is on, start them moving
            if (game.random_mode) {
                const entity = game.next_entity_id - 1;
                const target = game.randomNode();
                game.engine.requestPath(entity, target) catch {};
            }
        }
        game.message = "Added 5 entities";
        game.message_timer = 1.0;
    }

    // - (minus) - Remove entities
    if (rl.isKeyPressed(.minus)) {
        const count_to_remove: u32 = @min(5, game.next_entity_id);
        if (count_to_remove > 0) {
            for (0..count_to_remove) |_| {
                if (game.next_entity_id > 0) {
                    game.next_entity_id -= 1;
                    game.engine.unregisterEntity(game.next_entity_id);

                    // Adjust selected entity if needed
                    if (game.selected_entity) |sel| {
                        if (sel >= game.next_entity_id) {
                            game.selected_entity = if (game.next_entity_id > 0) game.next_entity_id - 1 else null;
                        }
                    }
                }
            }
            game.message = "Removed entities";
            game.message_timer = 1.0;
        }
    }

    // S - Cycle stair mode
    if (rl.isKeyPressed(.s)) {
        // Cycle: all -> single -> direction -> all
        game.stair_mode = switch (game.stair_mode) {
            .all => .single,
            .single => .direction,
            .direction => .all,
            .none => .all,
        };

        // Rebuild the building with new stair mode
        rebuildBuilding(game) catch {
            game.message = "Failed to rebuild!";
            game.message_timer = 2.0;
            return;
        };

        game.message = switch (game.stair_mode) {
            .all => "Stair mode: ALL (unlimited)",
            .single => "Stair mode: SINGLE (one at a time)",
            .direction => "Stair mode: DIRECTION (same dir only)",
            .none => "Stair mode: NONE",
        };
        game.message_timer = 2.0;
    }
}

fn selectEntity(game: *Game, id: u32) void {
    if (id < game.next_entity_id and game.engine.getPosition(id) != null) {
        game.selected_entity = id;
    }
}

fn updateMessage(game: *Game, delta: f32) void {
    if (game.message_timer > 0) {
        game.message_timer -= delta;
        if (game.message_timer <= 0) {
            game.message = "Click a node to move the entity";
        }
    }
}

fn findNearestNode(engine: *Engine, x: f32, y: f32, max_dist: f32) ?u32 {
    var nearest: ?u32 = null;
    var nearest_dist: f32 = max_dist * max_dist;

    var i: u32 = 0;
    while (i < @as(u32, @intCast(engine.getNodeCount()))) : (i += 1) {
        if (engine.getNodePosition(i)) |pos| {
            const dx = pos.x - x;
            const dy = pos.y - y;
            const dist = dx * dx + dy * dy;
            if (dist < nearest_dist) {
                nearest_dist = dist;
                nearest = i;
            }
        }
    }
    return nearest;
}

fn drawBuilding(game: *Game) void {
    const engine = game.engine;
    const floors = game.floor_count;

    // Draw floor backgrounds
    for (0..floors) |floor_idx| {
        const floor: u32 = @intCast(floor_idx);
        const y: i32 = @intFromFloat(FLOOR_Y_OFFSET + @as(f32, @floatFromInt(floors - 1 - floor)) * FLOOR_HEIGHT - 30);

        rl.drawRectangle(50, y, 820, 100, COLORS.floor_bg);
        rl.drawRectangleLines(50, y, 820, 100, COLORS.floor_border);

        // Floor label
        var buf: [16]u8 = undefined;
        const label = std.fmt.bufPrintZ(&buf, "Floor {d}", .{floor + 1}) catch "?";
        rl.drawText(label, 55, y + 5, 14, COLORS.text_dim);
    }

    // Draw edges
    var i: u32 = 0;
    while (i < @as(u32, @intCast(engine.getNodeCount()))) : (i += 1) {
        if (engine.getNodePosition(i)) |from_pos| {
            if (engine.getDirectionalEdges(i)) |edges| {
                // Draw right edge
                if (edges.right) |to_id| {
                    if (engine.getNodePosition(to_id)) |to_pos| {
                        rl.drawLineEx(
                            .{ .x = from_pos.x, .y = from_pos.y },
                            .{ .x = to_pos.x, .y = to_pos.y },
                            2,
                            COLORS.edge,
                        );
                    }
                }
                // Draw vertical edges (stairs)
                if (edges.up) |to_id| {
                    if (engine.getNodePosition(to_id)) |to_pos| {
                        rl.drawLineEx(
                            .{ .x = from_pos.x, .y = from_pos.y },
                            .{ .x = to_pos.x, .y = to_pos.y },
                            3,
                            COLORS.stair_edge,
                        );
                    }
                }
            }
        }
    }

    // Draw nodes
    i = 0;
    while (i < @as(u32, @intCast(engine.getNodeCount()))) : (i += 1) {
        if (engine.getNodePosition(i)) |pos| {
            const stair_mode = engine.getStairMode(i);
            const is_stair = stair_mode != .none;

            // Determine stair color based on state
            var color = if (is_stair) COLORS.stair else COLORS.node;
            var outline = if (is_stair) COLORS.stair_outline else COLORS.node_outline;

            if (is_stair) {
                if (engine.getStairState(i)) |state| {
                    if (state.users_count > 0) {
                        color = COLORS.stair_occupied;
                        outline = rl.Color.init(255, 150, 150, 255);
                    }
                }
                // Different outline for single mode
                if (stair_mode == .single) {
                    outline = COLORS.stair_single;
                }
            }

            const x: i32 = @intFromFloat(pos.x);
            const y: i32 = @intFromFloat(pos.y);

            // Draw stair indicator (vertical line)
            if (is_stair) {
                const edge_color = if (engine.getStairState(i)) |state|
                    if (state.users_count > 0) COLORS.stair_occupied else COLORS.stair_edge
                else
                    COLORS.stair_edge;
                rl.drawRectangle(x - 3, y - NODE_RADIUS - 8, 6, NODE_RADIUS * 2 + 16, edge_color);
            }

            rl.drawCircle(x, y, NODE_RADIUS, outline);
            rl.drawCircle(x, y, NODE_RADIUS - 2, color);

            // Node ID
            var buf: [8]u8 = undefined;
            const id_str = std.fmt.bufPrintZ(&buf, "{d}", .{i}) catch "?";
            const text_x = x - @divFloor(@as(i32, @intCast(id_str.len)) * 4, 2);
            rl.drawText(id_str, text_x, y - 5, 10, COLORS.text);

            // Show stair mode indicator for single/direction
            if (is_stair and stair_mode != .all) {
                const mode_char: [:0]const u8 = switch (stair_mode) {
                    .single => "S",
                    .direction => "D",
                    else => "",
                };
                rl.drawText(mode_char, x - 3, y - NODE_RADIUS - 20, 10, COLORS.text);
            }
        }
    }
}

fn drawEntities(game: *Game) void {
    const engine = game.engine;

    var i: u32 = 0;
    while (i < game.next_entity_id) : (i += 1) {
        // Use getPositionFull to check waiting state
        if (engine.getPositionFull(i)) |full_pos| {
            const is_selected = if (game.selected_entity) |sel| sel == i else false;
            const is_waiting = full_pos.waiting_for_stair != null;

            const color = if (is_selected)
                COLORS.entity_selected
            else if (is_waiting)
                COLORS.entity_waiting
            else
                COLORS.entity;

            const x: i32 = @intFromFloat(full_pos.x);
            const y: i32 = @intFromFloat(full_pos.y);

            // Shadow
            rl.drawCircle(x + 2, y + 2, ENTITY_RADIUS, rl.Color.init(0, 0, 0, 80));

            // Entity
            rl.drawCircle(x, y, ENTITY_RADIUS, color);

            // Selection ring
            if (is_selected) {
                rl.drawCircleLines(x, y, ENTITY_RADIUS + 5, color);
                rl.drawCircleLines(x, y, ENTITY_RADIUS + 6, color);
            }

            // Waiting indicator (pulsing ring)
            if (is_waiting) {
                rl.drawCircleLines(x, y, ENTITY_RADIUS + 3, COLORS.entity_waiting);
            }

            // Entity ID
            var buf: [8]u8 = undefined;
            const id_str = std.fmt.bufPrintZ(&buf, "{d}", .{i}) catch "?";
            rl.drawText(id_str, x - 4, y - 5, 12, COLORS.bg);

            // Moving/Waiting indicator
            if (is_waiting) {
                rl.drawText("W", x + ENTITY_RADIUS + 3, y - 5, 10, COLORS.entity_waiting);
            } else if (engine.isMoving(i)) {
                rl.drawText("->", x + ENTITY_RADIUS + 3, y - 5, 10, color);
            }
        }
    }
}

fn drawUI(game: *Game) void {
    // Info panel
    rl.drawRectangle(WINDOW_WIDTH - 250, 10, 240, 180, COLORS.panel);
    rl.drawRectangleLines(WINDOW_WIDTH - 250, 10, 240, 180, COLORS.panel_border);

    rl.drawText("Multi-Floor Building", WINDOW_WIDTH - 240, 20, 16, COLORS.title);

    var buf: [64]u8 = undefined;

    // Stats
    const stats = std.fmt.bufPrintZ(&buf, "Floors: {d}  Nodes: {d}", .{
        game.floor_count,
        game.engine.getNodeCount(),
    }) catch "?";
    rl.drawText(stats, WINDOW_WIDTH - 240, 45, 12, COLORS.text);

    const entity_stats = std.fmt.bufPrintZ(&buf, "Entities: {d}", .{game.next_entity_id}) catch "?";
    rl.drawText(entity_stats, WINDOW_WIDTH - 240, 65, 12, COLORS.text);

    // Selected entity info
    if (game.selected_entity) |sel| {
        const sel_str = std.fmt.bufPrintZ(&buf, "Selected: Entity {d}", .{sel}) catch "?";
        rl.drawText(sel_str, WINDOW_WIDTH - 240, 90, 12, COLORS.entity_selected);

        if (game.engine.getCurrentNode(sel)) |node| {
            const floor = node / game.nodes_per_floor + 1;
            const node_str = std.fmt.bufPrintZ(&buf, "  Node {d} (Floor {d})", .{ node, floor }) catch "?";
            rl.drawText(node_str, WINDOW_WIDTH - 240, 108, 11, COLORS.text_dim);
        }

        if (game.engine.isMoving(sel)) {
            rl.drawText("  Status: Moving", WINDOW_WIDTH - 240, 124, 11, COLORS.stair);
        } else {
            rl.drawText("  Status: Idle", WINDOW_WIDTH - 240, 124, 11, COLORS.text_dim);
        }
    }

    // Message
    rl.drawText(game.message, WINDOW_WIDTH - 240, 150, 11, COLORS.text_dim);

    // Legend
    rl.drawRectangle(WINDOW_WIDTH - 250, 200, 240, 110, COLORS.panel);
    rl.drawRectangleLines(WINDOW_WIDTH - 250, 200, 240, 110, COLORS.panel_border);

    rl.drawText("Legend:", WINDOW_WIDTH - 240, 210, 12, COLORS.text);
    rl.drawCircle(WINDOW_WIDTH - 225, 235, 6, COLORS.node);
    rl.drawText("Room", WINDOW_WIDTH - 210, 230, 11, COLORS.text_dim);
    rl.drawCircle(WINDOW_WIDTH - 145, 235, 6, COLORS.stair);
    rl.drawText("Staircase", WINDOW_WIDTH - 130, 230, 11, COLORS.text_dim);
    rl.drawCircle(WINDOW_WIDTH - 225, 260, 6, COLORS.entity);
    rl.drawText("Entity", WINDOW_WIDTH - 210, 255, 11, COLORS.text_dim);
    rl.drawCircle(WINDOW_WIDTH - 145, 260, 6, COLORS.entity_waiting);
    rl.drawText("Waiting", WINDOW_WIDTH - 130, 255, 11, COLORS.text_dim);
    rl.drawCircle(WINDOW_WIDTH - 225, 285, 6, COLORS.stair_occupied);
    rl.drawText("Occupied", WINDOW_WIDTH - 210, 280, 11, COLORS.text_dim);

    // Current stair mode
    const mode_text: [:0]const u8 = switch (game.stair_mode) {
        .all => "Mode: ALL",
        .single => "Mode: SINGLE",
        .direction => "Mode: DIRECTION",
        .none => "Mode: NONE",
    };
    rl.drawText(mode_text, WINDOW_WIDTH - 145, 280, 11, COLORS.title);

    // Controls
    rl.drawText("Click: Move | R: Reset | N: Random | V: Speed | S: Stair Mode | =/- : Entities", 10, WINDOW_HEIGHT - 25, 11, COLORS.text_dim);

    // Status indicators
    if (game.random_mode) {
        rl.drawRectangle(WINDOW_WIDTH - 250, 290, 240, 25, COLORS.stair);
        rl.drawText("RANDOM MODE ACTIVE", WINDOW_WIDTH - 235, 296, 12, COLORS.bg);
    }

    if (game.speed_multiplier > 1.0) {
        var speed_buf: [32]u8 = undefined;
        const speed_text = std.fmt.bufPrintZ(&speed_buf, "Speed: {d:.1}x", .{game.speed_multiplier}) catch "?";
        rl.drawText(speed_text, WINDOW_WIDTH - 240, 320, 12, COLORS.title);
    }
}

fn onPathCompleted(game: *Game, entity: u32, _: u32) void {
    // In random mode, send entity to a new random node
    if (game.random_mode) {
        const target = game.randomNode();
        game.engine.requestPath(entity, target) catch {};
    }

    if (game.selected_entity) |sel| {
        if (sel == entity and !game.random_mode) {
            game.message = "Arrived!";
            game.message_timer = 1.5;
        }
    }
}
