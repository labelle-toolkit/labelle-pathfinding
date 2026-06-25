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

/// Movement target — directs an entity to move towards a position.
/// Parameterized on the game's Action enum.
pub fn MovementTargetWith(comptime ActionType: type) type {
    return struct {
        target_x: f32,
        target_y: f32,
        speed: f32 = 200.0,
        action: ActionType,
    };
}

/// Navigation intent — requests pathfinder-based navigation to a target.
/// Lifecycle: pending → navigating → removed on arrival at destination CMN.
/// Parameterized on the game's Action enum.
pub fn NavigationIntentWith(comptime ActionType: type) type {
    return struct {
        /// Entity to navigate to.
        target_entity: u64 = 0,
        /// What to do when we arrive.
        action: ActionType,
        /// Cached world position of target (for pathfinder routing).
        target_x: f32 = 0,
        target_y: f32 = 0,
        /// Resolved closest node of target (0xFFFFFFFF = unresolved).
        target_node: u32 = 0xFFFFFFFF,
        /// Current state in the navigation lifecycle.
        state: State = .pending,

        pub const State = enum {
            /// Just set, needs pathfinder navigate() call.
            pending,
            /// Pathfinder is actively moving entity node-to-node.
            navigating,
        };
    };
}
