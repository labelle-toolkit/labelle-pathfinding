// Pathfinder ECS components
//
// These component types are owned by the pathfinder library and re-exported
// by the game's component files.

/// A navigation graph node. The entity's Position determines the node's
/// world coordinates; `node_id` is assigned at runtime by the pathfinder.
pub const MovementNode = struct {
    pub const save_policy: @import("labelle-core").SavePolicy = .saveable;
    pub const skip_fields = .{"node_id"};
    pub const entity_ref_fields = .{};

    node_id: u32 = 0,
};

/// Marker: this MovementNode is a stair connection point.
/// When present, the pathfinder connects this node horizontally (same Y axis)
/// to other stair nodes, enabling cross-axis navigation.
pub const MovementStair = struct {
    pub const save_policy: @import("labelle-core").SavePolicy = .marker;

    _marker: u8 = 0,
};

/// Tracks the nearest navigation graph node for this entity.
/// Auto-assigned by the pathfinder during init to entities that have this component.
pub const ClosestMovementNode = struct {
    pub const save_policy: @import("labelle-core").SavePolicy = .transient;

    node_entity: u64 = 0,
    node_id: u32 = 0,
    distance: f32 = 0.0,
};

/// Per-entity walk speed in px/s, read by BOTH the graph walker and
/// `moveTo` direct walks. Attach it from game prefabs (worker.jsonc,
/// bandit.jsonc); entities without it walk at the plugin default
/// (`controller.DEFAULT_SPEED`).
///
/// Saveable on purpose: saved entities rehydrate their components from
/// the save file (not from prefab respawn), so a `.transient` policy
/// would silently reset every loaded entity to the default speed.
pub const MovementSpeed = struct {
    pub const save_policy: @import("labelle-core").SavePolicy = .saveable;

    speed: f32 = 200.0,
};

/// The persisted walk order — one per walking entity. Attached by
/// `Controller.navigate` / `Controller.moveTo`, removed when the walk
/// settles (arrival, failure, cancel, entity death).
///
/// Saveable so a mid-walk save resumes on load: `Controller.advance`
/// sweeps entities that carry `Navigating` but aren't tracked by the
/// live pathfinder (the tracker state is `.transient`) and re-issues
/// the walk from the entity's loaded position. Targets are world-space
/// positions, not entity refs, so no `entity_ref_fields` remapping is
/// needed across save/load.
pub const Navigating = struct {
    pub const save_policy: @import("labelle-core").SavePolicy = .saveable;

    target_x: f32 = 0,
    target_y: f32 = 0,
    mode: Mode = .graph,

    pub const Mode = enum {
        /// Route through the movement-node graph (Floyd-Warshall).
        graph,
        /// Straight-line walk to the target — off-graph moves (ship
        /// boundary hops, wander steps). No routing, just kinematics.
        direct,
    };
};

// (v4.0.0) The `MovementTargetWith` / `NavigationIntentWith` component
// factories are gone: the request-packet pattern they served moved into
// the plugin as `Navigating` + the `navigate`/`moveTo` commands, and the
// game-specific `action` payload they carried was dropped — arrival
// context lives in the caller's own state machine, announced via the
// `pathfinder__arrived` event.
