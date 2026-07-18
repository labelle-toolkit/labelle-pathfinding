//! Module root for `labelle-pathfinding` (v4).
//!
//! Everything lives in `pathfinding.zig` (re-exported wholesale below);
//! this file exists so the plugin's **Events** declaration sits at the
//! path the assembler AST-walks — `discoverPluginEvents` reads
//! `<plugin>/src/root.zig` literally and folds every
//! `pub const <name> = struct` inside a top-level
//! `pub const Events = struct { ... }` into the game's `PluginEvents`
//! union under the `<plugin>__<name>` tag. The struct must be declared
//! INLINE here (a re-export alias is invisible to the AST walk), and
//! payload field types must be self-contained for the same reason.

const pathfinding = @import("pathfinding.zig");

/// Game events emitted by the navigation Controller (v4 — the "events
/// up" half of the consolidation; see flying-platform's
/// docs/RFC-pathfinder-consolidation.md). Tag in the game's event
/// union: `pathfinder__<name>` (the plugin must be registered as
/// `.name = "pathfinder"` in project.labelle — the same requirement
/// `@import("pathfinder")` call sites already impose).
///
/// Events are sparse announcements (RFC-packs §6): walks settle
/// (arrived/failed), graphs rebuild, nodes die. Continuous state stays
/// behind the queries (`isNavigating`, `distance`, `walkDistance`).
pub const Events = struct {
    /// A walk settled at its destination — graph navigations, `moveTo`
    /// direct walks, and `.redundant` already-there calls all announce
    /// through this one event. `node_entity` is the MovementNode entity
    /// the walker settled at (0 when the arrival resolved off-graph).
    /// Arrival semantics (FSM transitions, job steps) belong to the
    /// subscribers — the plugin only reports the fact.
    pub const arrived = struct {
        entity: u64,
        node_entity: u64,
    };

    /// A walk ended WITHOUT arriving: the graph changed mid-walk and no
    /// reroute exists (`path_invalidated`), or a persisted order could
    /// not be re-issued after a load. The `Navigating` order is already
    /// removed when this fires — the owner decides whether to retry.
    ///
    /// (The `reason` field references the controller's `FailReason` by
    /// import — the assembler's AST walk only needs the event DECL
    /// itself inline in this file; field types resolve at compile time
    /// through the module graph like any other type.)
    pub const navigation_failed = struct {
        entity: u64,
        reason: pathfinding.FailReason,
    };

    /// The movement-node graph was (re)built; `epoch` is the new value
    /// of `Controller.graphEpoch()`. Push twin of the epoch poll —
    /// subscribe to invalidate any node-derived cache.
    pub const graph_rebuilt = struct {
        epoch: u64,
    };

    /// A node was tombstoned via `Controller.removeNode` (room
    /// deconstruction drains). The rebuild that follows announces
    /// separately via `graph_rebuilt`.
    pub const node_removed = struct {
        node_id: u32,
    };
};

// ── Full public surface — see `pathfinding.zig` for the docs ────────────────

// Controller (ECS adapter) + result types.
pub const Controller = pathfinding.Controller;
pub const ControllerState = pathfinding.ControllerState;
pub const Result = pathfinding.Result;
pub const Reason = pathfinding.Reason;
pub const FailReason = pathfinding.FailReason;
pub const controller = pathfinding.controller;

// Pure engine + graph.
pub const PathfinderWith = pathfinding.PathfinderWith;
pub const engine = pathfinding.engine;
pub const Graph = pathfinding.Graph;
pub const Config = pathfinding.Config;
pub const Edge = pathfinding.Edge;
pub const graph = pathfinding.graph;

// ECS components.
pub const components = pathfinding.components;
pub const MovementNode = pathfinding.MovementNode;
pub const MovementStair = pathfinding.MovementStair;
pub const ClosestMovementNode = pathfinding.ClosestMovementNode;
pub const Navigating = pathfinding.Navigating;
pub const MovementSpeed = pathfinding.MovementSpeed;
pub const Components = pathfinding.Components;

// Paths, hooks, gizmos, scalar types.
pub const MovementPath = pathfinding.MovementPath;
pub const movement_path = pathfinding.movement_path;
pub const NavigationHookPayload = pathfinding.NavigationHookPayload;
pub const GizmoCategories = pathfinding.GizmoCategories;
pub const NodeId = pathfinding.NodeId;
pub const Position = pathfinding.Position;
pub const INF = pathfinding.INF;
pub const distanceBetween = pathfinding.distanceBetween;
pub const FloydWarshall = pathfinding.FloydWarshall;

// Algorithm core (standalone).
pub const algo = pathfinding.algo;

// Pull the package's test tree into the unit-test build. The build's
// test root is THIS file (build.zig `unit_tests`), and Zig only
// collects tests from files referenced inside a collected test block —
// the decl re-exports above analyze `pathfinding.zig` but do not
// collect its `test { refAllDecls(nav); … }` chain. Without this block
// `zig build test` compiles and runs zero tests (found while adding
// the emitGameEvent tests for #52).
test {
    _ = pathfinding;
}
