//! Labelle Pathfinding
//!
//! Pathfinding + navigation for Zig game development, part of the labelle-toolkit.
//! Two layers, one package — and you can use either standalone:
//!
//! 1. **Navigation (the headline, top-level)** — `src/nav/`. An ECS-integrated
//!    `Controller` for labelle-engine games: you keep entity positions in your
//!    ECS (the single source of truth), and the Controller routes AND walks
//!    entities for you — graph navigation (`navigate`) and straight-line moves
//!    (`moveTo`), announced back as `pathfinder__*` game events, with a query
//!    surface (`reachable` / `walkDistance` / `isNavigating`) for reads. Built
//!    on the pure `PathfinderWith` engine, which is itself usable directly
//!    with no ECS. The Controller is duck-typed (`game: anytype`) — it never
//!    imports labelle-engine, so depending on this package never pulls the
//!    engine in.
//!
//! 2. **Algorithm core (`pathfinding.algo.*`)** — standalone, position-agnostic
//!    building blocks: A*, Floyd-Warshall (incl. SIMD/parallel variants),
//!    QuadTree spatial indexing, heuristics, grid helpers. No ECS, no game.
//!
//! ## Example — pure engine (no ECS, no game)
//! ```zig
//! const pf = @import("labelle_pathfinding");
//! var engine = pf.PathfinderWith(u64, struct {}){};
//! // build a graph, navigate, tick — you hold the engine.
//! ```
//!
//! ## Example — labelle-engine games (the Controller adapter)
//! ```zig
//! const pf = @import("labelle_pathfinding");
//! _ = pf.Controller.navigate(game, entity, target, @src());
//! ```
//!
//! ## Example — standalone A* / Floyd-Warshall
//! ```zig
//! const pf = @import("labelle_pathfinding");
//! var astar = pf.algo.AStar.init(allocator);
//! var fw = pf.algo.FloydWarshallOptimized(.{}).init(allocator);
//! ```

const std = @import("std");

// ── Navigation layer (headline) — re-exported at top level ──────────────────
// `src/nav/root.zig` is the navigation module (Controller + pure PathfinderWith
// engine + graph + components). Its public surface is promoted to the package
// top level so consumers use `pathfinding.Controller`, `pathfinding.MovementNode`,
// etc. directly.
const nav = @import("nav/root.zig");

// Controller (ECS adapter) + its result types.
pub const Controller = nav.Controller;
pub const ControllerState = nav.ControllerState;
pub const Result = nav.Result;
pub const Reason = nav.Reason;
pub const controller = nav.controller; // module (pub internals: thresholds, helpers)

// Pure engine + graph.
pub const PathfinderWith = nav.PathfinderWith;
pub const engine = nav.engine;
pub const Graph = nav.Graph;
pub const Config = nav.Config;
pub const Edge = nav.Edge;
pub const graph = nav.graph;

// ECS components.
pub const components = nav.components;
pub const MovementNode = nav.MovementNode;
pub const MovementStair = nav.MovementStair;
pub const ClosestMovementNode = nav.ClosestMovementNode;
pub const Navigating = nav.Navigating;
pub const MovementSpeed = nav.MovementSpeed;
// The `Components` aggregator the assembler scans to register the plugin's
// components (MovementNode / MovementStair / ClosestMovementNode /
// Navigating / MovementSpeed / ControllerState) into the ComponentRegistry.
pub const Components = nav.Components;

// Paths, hooks, gizmos, scalar types.
pub const MovementPath = nav.MovementPath;
pub const movement_path = nav.movement_path;
pub const NavigationHookPayload = nav.NavigationHookPayload;
pub const GizmoCategories = nav.GizmoCategories;
pub const NodeId = nav.NodeId;
pub const Position = nav.Position;
pub const INF = nav.INF;
pub const distanceBetween = nav.distanceBetween;
pub const FloydWarshall = nav.FloydWarshall; // the nav core's FW (zig_utils-backed)

// ── Algorithm core (standalone) — namespaced under `algo` ───────────────────
// Position-agnostic building blocks usable with no ECS / no game. Namespaced so
// their generic names (types, FloydWarshall, …) don't collide with the nav
// layer's top-level surface.
pub const algo = struct {
    pub const types = @import("types.zig");
    pub const ConnectionMode = types.ConnectionMode;
    pub const NodeData = types.NodeData;
    pub const NodePoint = types.NodePoint;
    pub const StairMode = types.StairMode;
    pub const VerticalDirection = types.VerticalDirection;
    pub const LogLevel = types.LogLevel;
    pub const FloydWarshallVariant = types.FloydWarshallVariant;
    pub const Grid = types.Grid;
    pub const GridConfig = types.GridConfig;
    pub const GridConnection = types.GridConnection;

    // Spatial indexing.
    pub const quad_tree = @import("quad_tree.zig");
    pub const QuadTree = quad_tree.QuadTree;
    pub const Rectangle = quad_tree.Rectangle;

    // Shortest-path algorithms.
    pub const FloydWarshall = @import("floyd_warshall.zig").FloydWarshall;
    pub const FloydWarshallWithHooks = @import("floyd_warshall.zig").FloydWarshallWithHooks;
    pub const AStar = @import("a_star.zig").AStar;
    pub const AStarWithHooks = @import("a_star.zig").AStarWithHooks;

    // Optimized Floyd-Warshall variants.
    pub const floyd_warshall_optimized = @import("floyd_warshall_optimized.zig");
    pub const FloydWarshallOptimized = floyd_warshall_optimized.FloydWarshallOptimized;
    pub const FloydWarshallParallel = floyd_warshall_optimized.FloydWarshallParallel;
    pub const FloydWarshallSimd = floyd_warshall_optimized.FloydWarshallSimd;
    pub const FloydWarshallScalar = floyd_warshall_optimized.FloydWarshallScalar;

    // Heuristics + the distance-graph interface.
    pub const heuristics = @import("heuristics.zig");
    pub const Heuristic = heuristics.Heuristic;
    pub const HeuristicFn = heuristics.HeuristicFn;
    pub const DistanceGraph = @import("distance_graph.zig").DistanceGraph;
    pub const validateDistanceGraph = @import("distance_graph.zig").validateDistanceGraph;
};

test {
    // Navigation layer + algorithm core.
    std.testing.refAllDecls(nav);
    std.testing.refAllDecls(algo);
    _ = @import("quad_tree.zig");
    _ = @import("floyd_warshall.zig");
    _ = @import("floyd_warshall_optimized.zig");
    _ = @import("a_star.zig");
    _ = @import("heuristics.zig");
}
