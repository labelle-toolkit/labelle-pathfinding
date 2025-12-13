//! labelle-pathfinding + labelle-engine Integration Example
//!
//! This example demonstrates how labelle-pathfinding's Components struct
//! integrates with labelle-engine's ComponentRegistryMulti for use in
//! .zon entity definitions.
//!
//! When labelle-pathfinding is added as a plugin to a labelle-engine project,
//! its exported Components (Vec2, NodeId, NodePoint) become available in the
//! component registry automatically.

const std = @import("std");
const engine = @import("labelle-engine");
const pathfinding = @import("pathfinding");

const print = std.debug.print;

// ============================================================================
// Component Registry Setup
// ============================================================================
// This is how the generated code would look when labelle-pathfinding is
// included as a plugin. The ComponentRegistryMulti merges engine built-ins
// with plugin components.

pub const Components = engine.ComponentRegistryMulti(.{
    // Base engine components
    struct {
        pub const Position = engine.Position;
        pub const Sprite = engine.Sprite;
        pub const Shape = engine.Shape;
        pub const Text = engine.Text;
    },
    // Plugin components from labelle-pathfinding
    // This is automatically included when the plugin is registered
    pathfinding.Components,
});

// ============================================================================
// Example Usage
// ============================================================================

pub fn main() !void {
    print("\n=== labelle-pathfinding + labelle-engine Integration ===\n\n", .{});

    // Demonstrate that pathfinding components are accessible through the registry
    print("1. Checking component availability in registry:\n", .{});
    print("   - Vec2: {}\n", .{Components.has("Vec2")});
    print("   - NodeId: {}\n", .{Components.has("NodeId")});
    print("   - NodePoint: {}\n", .{Components.has("NodePoint")});
    print("   - Position (engine): {}\n", .{Components.has("Position")});
    print("   - Sprite (engine): {}\n", .{Components.has("Sprite")});

    // Show the types
    print("\n2. Component type information:\n", .{});
    print("   - Vec2 type: {s}\n", .{@typeName(Components.getType("Vec2"))});
    print("   - NodeId type: {s}\n", .{@typeName(Components.getType("NodeId"))});
    print("   - NodePoint type: {s}\n", .{@typeName(Components.getType("NodePoint"))});

    // Create instances of pathfinding components
    print("\n3. Creating component instances:\n", .{});

    const vec2: pathfinding.Components.Vec2 = .{ .x = 100.0, .y = 200.0 };
    print("   - Vec2: ({d}, {d})\n", .{ vec2.x, vec2.y });

    const node_id: pathfinding.Components.NodeId = 42;
    print("   - NodeId: {d}\n", .{node_id});

    const node_point: pathfinding.Components.NodePoint = .{ .id = 5, .x = 150.0, .y = 250.0 };
    print("   - NodePoint: id={d}, pos=({d}, {d})\n", .{ node_point.id, node_point.x, node_point.y });

    // Demonstrate .zon-style usage (what would happen in scene files)
    print("\n4. Example .zon entity definition:\n", .{});
    print(
        \\   .components = .{{
        \\       .Vec2 = .{{ .x = 10.0, .y = 20.0 }},
        \\       .NodePoint = .{{ .id = 5, .x = 100, .y = 200 }},
        \\   }}
        \\
    , .{});

    print("\n=== Integration Example Complete ===\n\n", .{});
}
