//! Raylib Pathfinding Visualization Example
//!
//! Interactive demo showing pathfinding with visual entities.
//! Click on nodes to set the target for the entity.
//!
//! Controls:
//! - Left Click: Set entity target to nearest node
//! - R: Reset entity to start position
//! - Space: Add a new entity at a random node

const std = @import("std");
const pathfinding = @import("pathfinding");
const rl = @import("raylib");

const PathfindingEngine = pathfinding.PathfindingEngine;

// Configuration
const WINDOW_WIDTH = 800;
const WINDOW_HEIGHT = 600;
const NODE_RADIUS = 12;
const ENTITY_RADIUS = 16;

const Config = struct {
    pub const Entity = u32;
    pub const Context = *Game;
    pub const log_level = pathfinding.LogLevel.none;
};

const Engine = PathfindingEngine(Config);

const Game = struct {
    engine: *Engine,
    next_entity_id: u32 = 1,
    selected_entity: ?u32 = null,
    message: [:0]const u8 = "Click a node to move the entity",
    message_timer: f32 = 0,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize engine
    var engine = try Engine.init(allocator);
    defer engine.deinit();

    // Create game state
    var game = Game{
        .engine = &engine,
    };

    // Setup callbacks
    engine.on_node_reached = onNodeReached;
    engine.on_path_completed = onPathCompleted;

    // Build the node graph
    try setupGraph(&engine);

    // Register initial entity
    const start_node = engine.getNodePosition(0).?;
    try engine.registerEntity(0, start_node.x, start_node.y, 150.0);
    game.selected_entity = 0;

    // Initialize Raylib
    rl.initWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Labelle Pathfinding - Raylib Demo");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) {
        const delta = rl.getFrameTime();

        // Handle input
        handleInput(&game);

        // Update pathfinding
        engine.tick(&game, delta);

        // Update message timer
        if (game.message_timer > 0) {
            game.message_timer -= delta;
            if (game.message_timer <= 0) {
                game.message = "Click a node to move the entity";
            }
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.init(26, 26, 46, 255));

        drawGraph(&engine);
        drawEntities(&game);
        drawUI(&game);
    }
}

fn setupGraph(engine: *Engine) !void {
    // Create a more interesting graph layout
    const nodes = [_]struct { x: f32, y: f32 }{
        // Top row
        .{ .x = 100, .y = 80 },
        .{ .x = 250, .y = 80 },
        .{ .x = 400, .y = 80 },
        .{ .x = 550, .y = 80 },
        .{ .x = 700, .y = 80 },
        // Upper middle
        .{ .x = 175, .y = 180 },
        .{ .x = 325, .y = 180 },
        .{ .x = 475, .y = 180 },
        .{ .x = 625, .y = 180 },
        // Center
        .{ .x = 100, .y = 300 },
        .{ .x = 250, .y = 300 },
        .{ .x = 400, .y = 300 },
        .{ .x = 550, .y = 300 },
        .{ .x = 700, .y = 300 },
        // Lower middle
        .{ .x = 175, .y = 420 },
        .{ .x = 325, .y = 420 },
        .{ .x = 475, .y = 420 },
        .{ .x = 625, .y = 420 },
        // Bottom row
        .{ .x = 100, .y = 520 },
        .{ .x = 250, .y = 520 },
        .{ .x = 400, .y = 520 },
        .{ .x = 550, .y = 520 },
        .{ .x = 700, .y = 520 },
    };

    for (nodes, 0..) |node, i| {
        try engine.addNode(@intCast(i), node.x, node.y);
    }

    // Connect nodes
    try engine.connectNodes(.{
        .omnidirectional = .{
            .max_distance = 200,
            .max_connections = 4,
        },
    });
    try engine.rebuildPaths();
}

fn handleInput(game: *Game) void {
    const mouse_pos = rl.getMousePosition();

    // Left click - set target
    if (rl.isMouseButtonPressed(.left)) {
        if (game.selected_entity) |entity| {
            // Find nearest node to mouse
            if (findNearestNode(game.engine, mouse_pos.x, mouse_pos.y, 50)) |node_id| {
                game.engine.requestPath(entity, node_id) catch {
                    game.message = "No path to target!";
                    game.message_timer = 2.0;
                    return;
                };
                game.message = "Moving to target...";
                game.message_timer = 1.0;
            }
        }
    }

    // R - Reset entity
    if (rl.isKeyPressed(.r)) {
        if (game.selected_entity) |entity| {
            game.engine.cancelPath(entity);
            const start = game.engine.getNodePosition(0).?;
            game.engine.unregisterEntity(entity);
            game.engine.registerEntity(entity, start.x, start.y, 150.0) catch {};
            game.message = "Entity reset";
            game.message_timer = 1.0;
        }
    }

    // Space - Add new entity
    if (rl.isKeyPressed(.space)) {
        const node_id: u32 = @intCast(@mod(game.next_entity_id * 7, game.engine.getNodeCount()));
        if (game.engine.getNodePosition(node_id)) |pos| {
            game.engine.registerEntity(game.next_entity_id, pos.x, pos.y, 120.0 + @as(f32, @floatFromInt(game.next_entity_id)) * 10) catch {};
            game.selected_entity = game.next_entity_id;
            game.next_entity_id += 1;
            game.message = "New entity added";
            game.message_timer = 1.0;
        }
    }

    // Tab - Cycle through entities
    if (rl.isKeyPressed(.tab)) {
        if (game.selected_entity) |current| {
            const next = (current + 1) % game.next_entity_id;
            if (game.engine.getPosition(next) != null) {
                game.selected_entity = next;
            } else {
                game.selected_entity = 0;
            }
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

fn drawGraph(engine: *Engine) void {
    const edge_color = rl.Color.init(15, 52, 96, 255);
    const node_outline = rl.Color.init(0, 212, 255, 255);
    const node_fill = rl.Color.init(15, 52, 96, 255);

    // Draw edges
    var i: u32 = 0;
    while (i < @as(u32, @intCast(engine.getNodeCount()))) : (i += 1) {
        if (engine.getNodePosition(i)) |from_pos| {
            if (engine.getEdges(i)) |edges| {
                for (edges) |to_id| {
                    if (engine.getNodePosition(to_id)) |to_pos| {
                        rl.drawLine(
                            @intFromFloat(from_pos.x),
                            @intFromFloat(from_pos.y),
                            @intFromFloat(to_pos.x),
                            @intFromFloat(to_pos.y),
                            edge_color,
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
            // Node outline
            rl.drawCircle(
                @intFromFloat(pos.x),
                @intFromFloat(pos.y),
                NODE_RADIUS,
                node_outline,
            );
            // Node fill
            rl.drawCircle(
                @intFromFloat(pos.x),
                @intFromFloat(pos.y),
                NODE_RADIUS - 2,
                node_fill,
            );
        }
    }
}

fn drawEntities(game: *Game) void {
    const engine = game.engine;
    const selected = game.selected_entity;

    const selected_color = rl.Color.init(74, 222, 128, 255);
    const entity_color = rl.Color.init(0, 212, 255, 255);
    const text_color = rl.Color.init(26, 26, 46, 255);

    var i: u32 = 0;
    while (i < game.next_entity_id) : (i += 1) {
        if (engine.getPosition(i)) |pos| {
            const is_selected = if (selected) |sel| sel == i else false;
            const color = if (is_selected) selected_color else entity_color;

            // Draw entity
            rl.drawCircle(
                @intFromFloat(pos.x),
                @intFromFloat(pos.y),
                ENTITY_RADIUS,
                color,
            );

            // Draw selection ring
            if (is_selected) {
                rl.drawCircleLines(
                    @intFromFloat(pos.x),
                    @intFromFloat(pos.y),
                    ENTITY_RADIUS + 4,
                    selected_color,
                );
            }

            // Draw entity ID
            var buf: [8]u8 = undefined;
            const id_str = std.fmt.bufPrintZ(&buf, "{d}", .{i}) catch "?";
            rl.drawText(
                id_str,
                @as(i32, @intFromFloat(pos.x)) - 4,
                @as(i32, @intFromFloat(pos.y)) - 6,
                12,
                text_color,
            );
        }
    }
}

fn drawUI(game: *Game) void {
    const panel_bg = rl.Color.init(22, 33, 62, 230);
    const panel_border = rl.Color.init(0, 212, 255, 255);
    const title_color = rl.Color.init(0, 212, 255, 255);
    const text_color = rl.Color.init(200, 200, 200, 255);
    const dim_color = rl.Color.init(100, 100, 100, 255);

    // Background panel
    rl.drawRectangle(10, 10, 250, 90, panel_bg);
    rl.drawRectangleLines(10, 10, 250, 90, panel_border);

    // Title
    rl.drawText("Labelle Pathfinding", 20, 20, 16, title_color);

    // Stats
    var buf: [64]u8 = undefined;
    const stats = std.fmt.bufPrintZ(&buf, "Entities: {d}  Nodes: {d}", .{
        game.engine.getEntityCount(),
        game.engine.getNodeCount(),
    }) catch "Error";
    rl.drawText(stats, 20, 45, 12, text_color);

    // Message
    rl.drawText(game.message, 20, 70, 12, text_color);

    // Controls help
    rl.drawText("Click: Move | R: Reset | Space: Add | Tab: Select", 10, WINDOW_HEIGHT - 25, 12, dim_color);
}

fn onNodeReached(_: *Game, _: u32, _: u32) void {
    // Could add visual feedback here
}

fn onPathCompleted(game: *Game, _: u32, _: u32) void {
    game.message = "Destination reached!";
    game.message_timer = 2.0;
}
