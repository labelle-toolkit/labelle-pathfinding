pub const types = @import("types.zig");
pub const graph = @import("graph.zig");
pub const floyd_warshall = @import("floyd_warshall.zig");
pub const hooks = @import("hooks.zig");
pub const movement_path = @import("movement_path.zig");
pub const engine = @import("engine.zig");

// Core types
pub const NodeId = types.NodeId;
pub const Position = types.Position;
pub const INF = types.INF;
pub const distanceBetween = types.distanceBetween;

// Graph
pub const Graph = graph.Graph;
pub const Config = graph.Config;
pub const Edge = graph.Edge;

// Floyd-Warshall
pub const FloydWarshall = floyd_warshall.FloydWarshall;

// Hooks
pub const NavigationHookPayload = hooks.NavigationHookPayload;

// Movement
pub const MovementPath = movement_path.MovementPath;

// Engine (main game-facing API)
pub const PathfinderWith = engine.PathfinderWith;

/// Gizmo categories — discovered by the engine at comptime.
/// Scripts use these IDs with drawGizmo*Category() for grouped toggling.
pub const GizmoCategories = struct {
    pub const Workers: u8 = 1;
    pub const Navigation: u8 = 2;
    pub const Production: u8 = 3;
    pub const HUD: u8 = 4;
};

// ECS components
pub const components = @import("components.zig");
pub const MovementNode = components.MovementNode;
pub const MovementStair = components.MovementStair;
pub const ClosestMovementNode = components.ClosestMovementNode;
pub const MovementTargetWith = components.MovementTargetWith;
pub const NavigationIntentWith = components.NavigationIntentWith;

// (The legacy `PathfinderContext` ECS adapter was dropped during the move into
// labelle-pathfinding — use `Controller` exclusively.)

// Plugin-exported Controller (RFC-plugin-controllers §1/§2). The
// assembler's `PluginControllers` dispatcher auto-wires setup/deinit
// on scene load/unload; game scripts call into the public API via
// `pathfinder.Controller.navigate / .cancel / .findClosestNode`. The
// per-frame `advance` method is invoked by a plugin-shipped script
// at `libs/pathfinder/scripts/playing/01_advance.zig`.
// The controller submodule is re-exported under `controller` alongside
// the other file-level namespaces (types/graph/floyd_warshall above)
// so tests can reach pub internals like `cachedNearestStillValid`
// without widening the top-level module API. Downstream code should
// keep using `pathfinder.Controller` for the actual Controller struct.
pub const controller = @import("controller.zig");
pub const Controller = controller.Controller;
pub const ControllerState = controller.ControllerState;
pub const Result = controller.Result;
pub const Reason = controller.Reason;

/// Components exported for ECS integration.
/// Auto-discovered by the CLI when this plugin is declared.
pub const Components = struct {
    pub const MovementNode = components.MovementNode;
    pub const MovementStair = components.MovementStair;
    pub const ClosestMovementNode = components.ClosestMovementNode;
    /// Singleton component holding the Controller's runtime state
    /// (RFC-plugin-controllers §6, primary pattern). Transient — never
    /// persisted.
    pub const ControllerState = controller.ControllerState;
};
