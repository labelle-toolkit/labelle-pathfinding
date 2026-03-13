//! labelle-pathfinding + labelle-engine Integration Example
//!
//! This example demonstrates how labelle-pathfinding's Components struct
//! integrates with labelle-engine's ComponentRegistryMulti for use in
//! .zon entity definitions.
//!
//! When labelle-pathfinding is added as a plugin to a labelle-engine project,
//! its exported Components (Position, NodeId, NodePoint, MovementNode, ClosestMovementNode) become available in the
//! component registry automatically.

const std = @import("std");
const engine = @import("labelle-engine");
const pathfinding = @import("labelle_pathfinding");

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
    print("   - Position: {}\n", .{Components.has("Position")});
    print("   - NodeId: {}\n", .{Components.has("NodeId")});
    print("   - NodePoint: {}\n", .{Components.has("NodePoint")});
    print("   - Sprite (engine): {}\n", .{Components.has("Sprite")});

    // Show the types
    print("\n2. Component type information:\n", .{});
    print("   - Position type: {s}\n", .{@typeName(Components.getType("Position"))});
    print("   - NodeId type: {s}\n", .{@typeName(Components.getType("NodeId"))});
    print("   - NodePoint type: {s}\n", .{@typeName(Components.getType("NodePoint"))});

    // Create instances of pathfinding components
    print("\n3. Creating component instances:\n", .{});

    const pos: pathfinding.Components.Position = .{ .x = 100.0, .y = 200.0 };
    print("   - Position: ({d:.1}, {d:.1})\n", .{ pos.x, pos.y });

    const node_id: pathfinding.Components.NodeId = 42;
    print("   - NodeId: {d}\n", .{node_id});

    const node_point: pathfinding.Components.NodePoint = .{ .id = 5, .x = 150.0, .y = 250.0 };
    print("   - NodePoint: id={d}, pos=({d:.1}, {d:.1})\n", .{ node_point.id, node_point.x, node_point.y });

    // Demonstrate .zon-style usage (what would happen in scene files)
    print("\n4. Example .zon entity definition:\n", .{});
    print(
        \\   .components = .{{
        \\       .Position = .{{ .x = 10.0, .y = 20.0 }},
        \\       .NodePoint = .{{ .id = 5, .x = 100, .y = 200 }},
        \\   }}
        \\
    , .{});

    print("\n=== Integration Example Complete ===\n\n", .{});
}
