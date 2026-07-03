// Plugin-exported Controller for the pathfinder.
//
// Per RFC-plugin-controllers §1/§2: the plugin's root module exports a
// `pub const Controller = struct { setup, deinit, ... }` so the assembler
// auto-wires `setup` on scene-load and `deinit` on scene-unload, and
// re-exports the API to game scripts as `pathfinder.Controller.*`.
//
// This supersedes the game-side `scripts/playing/01_pathfinder_bridge.zig`
// bridge that used to re-derive the library's mutator API in ~580 lines.
//
// State storage (RFC §6, primary pattern): the Controller owns a singleton
// ECS component `ControllerState` whose `state_ptr` field (a `usize`
// holding a type-erased pointer) references a heap-allocated `State`
// holding the graph, node→entity map, and pending-entities ring.
// `setup` creates the singleton entity + state; `deinit` frees both.
// Every public method looks up the singleton via the active world's
// ECS backend — no module-level `var`.
//
// Scope — what lives here vs. the caller (v4, the consolidation):
//   Plugin (here):   graph build, node registration, per-frame tick,
//                    BOTH walkers (graph + `moveTo` straight-line),
//                    arrival/failure settling announced as
//                    `pathfinder__*` game events, the persisted
//                    `Navigating` order + its load-rehydration, CMN
//                    maintenance, and the query surface (reachable /
//                    walkDistance / isNavigating / distance).
//   Game:            a thin pause-gated driver that calls `advance`
//                    (the plugin can't read the game's pause component
//                    across the module boundary), hooks subscribing to
//                    the settle events for domain reactions (FSM
//                    transitions), and "can't move right now" rules —
//                    a fight/stun marker site must `cancel` the walk
//                    (the walker is domain-blind by design).

const std = @import("std");
const engine_mod = @import("engine.zig");
const components = @import("components.zig");
const types = @import("types.zig");
const movement_path = @import("movement_path.zig");

const MovementNode = components.MovementNode;
const MovementStair = components.MovementStair;
const ClosestMovementNode = components.ClosestMovementNode;
const Navigating = components.Navigating;
const MovementSpeed = components.MovementSpeed;

const NodeId = types.NodeId;
const Position = types.Position;

const log = std.log.scoped(.pathfinder_controller);

/// Hardcoded Game ID width. The flying-platform game uses u64 entity
/// handles (`@intCast`ed from the zig-ecs backend's Entity). Keeping
/// this as a constant inside the plugin avoids plumbing the game type
/// through every signature — callers always pass `game: anytype` and
/// the Controller casts to/from u64 at the boundary.
const GameId = u64;

const Pf = engine_mod.PathfinderWith(GameId, struct {});

/// Initial capacity for the pending-navigation ring. NOT a hard cap —
/// the ring is a growable `ArrayListUnmanaged`, so a 1000-worker colony
/// with hundreds of simultaneous in-flight navigations grows past this
/// rather than deferring (the old fixed `[32]` array silently throttled
/// navigation to 32 concurrent paths, the rest bouncing on a "ring full"
/// deferral every tick). Sized to a typical mid-colony's
/// concurrent-navigation count so steady state never reallocs.
const PENDING_INITIAL_CAPACITY: usize = 64;
/// Walk speed for entities without a `MovementSpeed` component, px/s.
pub const DEFAULT_SPEED: f32 = 200.0;
/// Arrival radius for `moveTo` direct walks, px. Matches the game-side
/// walker this replaced (flying-platform's `03_worker_movement`
/// `arrival_radius`) so straight-line arrival feel is unchanged. The
/// graph walker keeps its own tighter `ARRIVAL_THRESHOLD` (2 px,
/// `engine.zig`) — waypoints need precision, destinations need feel.
pub const DIRECT_ARRIVAL_RADIUS: f32 = 5.0;
/// Cap on **vertical** edge length — the climb between two stair
/// nodes on adjacent floors (same-X axis, different Y).
const MAX_VERTICAL_DISTANCE: f32 = 200.0;
/// Cap on **horizontal** edge length — corridor walking between
/// nodes on a single floor (same-Y axis, different X).
///
/// Tuned to half a slot width (78 px against `SLOT_WIDTH = 156`) so
/// a node connects to:
/// * Its in-room siblings (53-px stride) — well under the cap.
/// * The leftmost / rightmost node of an immediately adjacent room
///   (~50 px gap across the room boundary) — also under.
/// And does NOT connect across:
/// * A skipped cell (≥206-px gap from one room's right edge to the
///   next room's left edge across one missing cell). Was `300.0`
///   previously, which silently bridged corridor segments over
///   construction-site cells — workers visibly walked "over"
///   in-progress rooms. See FP issue #360.
const MAX_HORIZONTAL_DISTANCE: f32 = 78.0;

/// Maximum distance (px) between an entity's world position and a
/// movement node before `findNearestNodeInState` treats the entity
/// as off-graph (returns null). Without this, an entity placed
/// arbitrarily far from any walkable node would still snap to the
/// closest one and appear "on the graph" to `distance` /
/// `navigate` — so `pathfinder.Controller.distance` would say a
/// storage floating in mid-air 300 px from the nearest room is
/// reachable, and a navigate-to call would route through that
/// node and then visually walk the entity across empty space.
///
/// 100 px is about two-thirds of a room slot (`SLOT_WIDTH = 156`),
/// comfortably bigger than any observed in-room
/// "node-to-far-corner" distance — legitimate in-room entities
/// still snap. Anything farther is almost certainly a scene-layout
/// bug or an off-graph entity (ship, dangling item) that callers
/// should treat with off-graph helpers, not the snap-and-route
/// happy path.
pub const MAX_NODE_SNAP_DISTANCE: f32 = 100.0;

/// Linear (not squared) distance a cached entity position may drift
/// in the plane before `findNearestNodeForEntity` re-scans. The
/// squared value `CACHE_POS_THRESHOLD_SQ` below is what the hot-path
/// comparison uses — kept as a separate constant so the source of
/// truth stays in physical units.
///
/// 15 px ≈ half the minimum observed node spacing in the current
/// scene, which is a conservative upper bound on "close enough that
/// the cached node can't have been unseated by a sibling on the same
/// floor". Workers move at `DEFAULT_SPEED = 200 px/s` so a cache
/// entry lives for ≈ 75 ms of walking — multiple scheduler ticks'
/// worth of `distance()` calls coalesce into one real scan.
pub const CACHE_POS_THRESHOLD: f32 = 15.0;
const CACHE_POS_THRESHOLD_SQ: f32 = CACHE_POS_THRESHOLD * CACHE_POS_THRESHOLD;

/// Canonical Y-filter tolerance — the same 5-px slack
/// `findNearestNodeInState`'s "at or below" test uses. Kept as a
/// single source of truth so the scan predicate and the cache
/// validity check can't silently drift.
pub const Y_FILTER_EPS: f32 = 5.0;

/// Entry in `State.nearest_node_cache`. Stores both the entity
/// position the winner was resolved at (for in-plane drift check)
/// and the cached node's Y (for an exact re-application of the
/// Y-filter at lookup time — without it, the cache would go stale
/// silently when the entity drifts near a floor boundary). Exposed
/// as `pub` so the freshness-threshold test in
/// `tests/controller_cache_test.zig` can construct synthetic
/// entries — there's no in-tree production consumer outside this
/// file.
pub const CachedNearest = struct {
    node_id: NodeId,
    cached_x: f32,
    cached_y: f32,
    cached_node_y: f32,
};

/// One in-flight `moveTo` straight-line walk (see `State.direct_moves`).
pub const DirectMove = struct {
    target: Position,
    speed: f32,
};

/// Why a walk ended without arriving — the payload of the
/// `pathfinder__navigation_failed` event. Mirrors the reject/defer
/// `Reason`s a caller can also see synchronously from `navigate`, plus
/// the async-only `path_invalidated` (graph changed mid-walk, reroute
/// failed).
pub const FailReason = enum {
    path_invalidated,
    no_path,
    no_nearby_node,
    navigate_error,
};

/// Singleton ECS component attaching the Controller's runtime state to
/// a world entity. `state_ptr` is a `usize` holding a type-erased
/// pointer so the component doesn't pull game types into its shape;
/// the Controller owns the only cast.
///
/// Marked `.transient` — the state is rebuilt on every scene load by
/// `setup`, never persisted to save files.
pub const ControllerState = struct {
    pub const save_policy: @import("labelle-core").SavePolicy = .transient;

    state_ptr: usize = 0,
};

/// Heap-allocated runtime state. Not exported directly — callers reach
/// it through the Controller's methods, which look up the singleton
/// `ControllerState` component and cast `state_ptr` back to `*State`.
pub const State = struct {
    pf: Pf,
    allocator: std.mem.Allocator,
    /// Node-ID → entity lookup. Iteration order is deterministic
    /// (insertion order) so simulation replay is stable.
    node_entities: std.AutoArrayHashMapUnmanaged(u32, u64),
    /// Per-entity cache of `findNearestNode` results — #271's
    /// interim fix, upgraded in #271 to also cover moving entities.
    /// Populated lazily on first lookup via `findNearestNodeForEntity`;
    /// cleared on `rebuildGraph`. Turns the per-call O(N) scan over
    /// movement nodes into a constant-time lookup once the scheduler
    /// tick counts (W × S × distance queries) push past the low
    /// hundreds — see #271 for the scaling numbers.
    ///
    /// **Validity**: each entry stores the entity position at the
    /// time of cache population. A subsequent lookup returns the
    /// cached node iff the entity has moved less than
    /// `CACHE_POS_THRESHOLD` in-plane and less than `Y_FILTER_EPS`
    /// vertically. Beyond those bounds we re-scan (a floor change or
    /// enough lateral drift to potentially flip the nearest-node
    /// winner) and replace the entry. This keeps the cache correct
    /// for moving workers while still giving the scheduler cheap
    /// per-worker lookups across a tick's worth of `distance()`
    /// calls. Stationary entities (workstations, storage slots)
    /// trivially stay within the thresholds forever, so the original
    /// "lifetime cache for stationary targets" property is preserved.
    nearest_node_cache: std.AutoHashMap(u64, CachedNearest),
    /// Entities whose navigation the Controller tracks for arrival.
    /// Growable (not a fixed ring) so navigation throughput isn't capped
    /// — at 1000 workers hundreds can be in-flight at once. `addPending`
    /// appends, `removePending` / `processArrivals` swap-remove by index,
    /// `pendingEntities()` borrows `.items`.
    pending_entities: std.ArrayListUnmanaged(u64) = .empty,
    /// Persistent scratch for `pruneNearestNodeCache`'s two-pass
    /// dead-key collect. Cleared (not freed) each tick so the
    /// per-tick prune sweep is zero-alloc in steady state. Holds the
    /// `nearest_node_cache` keys whose entity no longer exists before
    /// they're removed from the map. See `pruneNearestNodeCache`.
    cache_prune_scratch: std.ArrayListUnmanaged(u64) = .empty,
    /// False until the first successful buildGraph. Stays false across
    /// the initial scene (e.g. `loading`) where no MovementNode
    /// entities exist; `advance` lazily builds once nodes appear.
    nodes_registered: bool = false,

    /// In-flight `moveTo` straight-line walks, keyed by entity. Kept
    /// OUT of the underlying pathfinder (these walks never touch the
    /// graph) and deliberately NOT cleared by `reset` — a graph
    /// rebuild doesn't invalidate a straight-line walk. Dead entities
    /// are pruned by the per-tick existence check in
    /// `advanceDirectMoves`.
    direct_moves: std.AutoArrayHashMapUnmanaged(u64, DirectMove) = .empty,

    /// Last graph epoch at which the CMN sweep ran — drives the
    /// epoch-change invalidation of `ClosestMovementNode` components
    /// (moved in from the game-side dispatch in v4).
    last_cmn_epoch: u64 = 0,

    /// Monotonic counter incremented every time the graph is
    /// (re)built — i.e. whenever the set of registered nodes
    /// changes. Game-side scripts consume this to detect when
    /// cached node assignments (e.g. `ClosestMovementNode` on
    /// storages, items, workers) need re-resolution after newly-
    /// built ladders/stairs added nodes the cached value couldn't
    /// have known about. See `Controller.graphEpoch`.
    graph_epoch: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) State {
        var pending: std.ArrayListUnmanaged(u64) = .empty;
        // Best-effort preallocation — a failure here just means the first
        // few appends grow it lazily, never a correctness issue.
        pending.ensureTotalCapacity(allocator, PENDING_INITIAL_CAPACITY) catch {};
        return .{
            .pf = Pf.init(allocator, .{
                .max_vertical_distance = MAX_VERTICAL_DISTANCE,
                .max_horizontal_distance = MAX_HORIZONTAL_DISTANCE,
            }),
            .allocator = allocator,
            .node_entities = .empty,
            .nearest_node_cache = std.AutoHashMap(u64, CachedNearest).init(allocator),
            .pending_entities = pending,
        };
    }

    pub fn deinit(self: *State) void {
        self.nearest_node_cache.deinit();
        self.node_entities.deinit(self.allocator);
        self.pending_entities.deinit(self.allocator);
        self.cache_prune_scratch.deinit(self.allocator);
        self.direct_moves.deinit(self.allocator);
        self.pf.deinit();
    }

    fn reset(self: *State, allocator: std.mem.Allocator) void {
        self.pf.deinit();
        self.node_entities.deinit(self.allocator);
        self.nearest_node_cache.deinit();
        self.pf = Pf.init(allocator, .{
            .max_vertical_distance = MAX_VERTICAL_DISTANCE,
            .max_horizontal_distance = MAX_HORIZONTAL_DISTANCE,
        });
        self.node_entities = .empty;
        self.nearest_node_cache = std.AutoHashMap(u64, CachedNearest).init(allocator);
        self.pending_entities.clearRetainingCapacity();
        self.cache_prune_scratch.clearRetainingCapacity();
        self.nodes_registered = false;
    }

    /// Returns `true` on success, `false` only on allocation failure
    /// (the ring grows, so it never "fills"). `navigate` checks the
    /// return value and surfaces a `.deferred` result — a silent drop
    /// would leave the entity moving in the underlying pathfinder
    /// without the Controller tracking it, and `processArrivals` would
    /// never fire the arrival signal.
    ///
    /// De-dupes against existing pending entries. `pf.navigate` already
    /// cancels any in-flight route for the same entity when re-entered,
    /// so the ring should hold each entity at most once. Without this
    /// check, scripts that replace a `NavigationIntent` (e.g. 07's
    /// `navigateToEntity`) would add a second entry for the same
    /// entity, and one of the two would leak forever (processArrivals
    /// only drops one per settle). The scan is O(pending) — acceptable
    /// because `navigate` removes the entity from the ring before
    /// re-adding, so this is a belt-and-suspenders pass over a list
    /// that's already deduped by construction.
    fn addPending(self: *State, entity_id: u64) bool {
        for (self.pending_entities.items) |existing| {
            if (existing == entity_id) return true;
        }
        self.pending_entities.append(self.allocator, entity_id) catch return false;
        return true;
    }

    fn removePending(self: *State, i: usize) void {
        _ = self.pending_entities.swapRemove(i);
    }

    pub fn isNavigating(self: *State, entity_id: u64) bool {
        return self.pf.isNavigating(entity_id);
    }
};

// ============================================================================
// Result type (RFC §2 — four-variant Result shape shared with WorkerController)
// ============================================================================

pub const Reason = enum {
    controller_not_setup,
    graph_not_built,
    no_position,
    no_nearby_node,
    no_path,
    navigate_error,
    /// Allocation failure growing the pending-navigation ring — the
    /// Controller couldn't track another in-flight navigation this
    /// tick. Transient under memory pressure; caller retries next
    /// frame. (The ring no longer has a fixed capacity, so this is
    /// OOM-only, not a "too many concurrent navigations" cap.)
    pending_alloc_failed,
};

pub const Result = union(enum) {
    /// Navigation was started and is now tracked by the Controller.
    accepted,
    /// Entity was already at the target node — nothing to do.
    redundant,
    /// Navigation couldn't start this tick but may succeed next tick
    /// (e.g. graph not yet built, no CMN resolved yet).
    deferred: Reason,
    /// Navigation cannot be resolved from this state.
    rejected: Reason,
};

pub const Controller = struct {
    /// Allocate the singleton State and attach `ControllerState` to a
    /// freshly-created entity. Called once by the assembler's generated
    /// `PluginControllers.setup` after scene load.
    ///
    /// Graph construction is deferred until `advance` sees MovementNode
    /// entities — the initial scene (e.g. `loading`) may have none.
    pub fn setup(game: anytype) !void {
        const allocator = game.allocator;

        // Allocate the fresh State up front so we can swap it into
        // either an existing singleton entity (scene reload path) or
        // a new one. Constructing it first also means the `errdefer`
        // cleanup covers the entity-reuse path.
        const st = try allocator.create(State);
        st.* = State.init(allocator);
        errdefer {
            st.deinit();
            allocator.destroy(st);
        }

        // Idempotent: if a singleton entity already exists (scene
        // reload / re-entry), free its old State and attach the new
        // one to the SAME entity. Previously we removed the component
        // but left the entity itself alive, leaking one empty entity
        // per scene load.
        if (findStateEntity(game)) |existing_entity| {
            if (game.active_world.ecs_backend.getComponent(existing_entity, ControllerState)) |cs| {
                if (cs.state_ptr != 0) {
                    const old: *State = @ptrFromInt(cs.state_ptr);
                    old.deinit();
                    allocator.destroy(old);
                }
                cs.state_ptr = @intFromPtr(st);
            } else {
                game.active_world.ecs_backend.addComponent(existing_entity, ControllerState{
                    .state_ptr = @intFromPtr(st),
                });
            }
            log.info("Controller setup: reused singleton entity {d}", .{existing_entity});
            return;
        }

        const entity = game.createEntity();
        game.active_world.ecs_backend.addComponent(entity, ControllerState{
            .state_ptr = @intFromPtr(st),
        });

        log.info("Controller setup: singleton state on entity {d}", .{entity});
    }

    /// Free the singleton State and remove its component. Loop backends
    /// invoke this via `defer` at the end of the init scope; callback
    /// backends invoke it from the cleanup callback.
    pub fn deinit(game: anytype) void {
        const entity = findStateEntity(game) orelse return;
        if (game.active_world.ecs_backend.getComponent(entity, ControllerState)) |cs| {
            if (cs.state_ptr != 0) {
                const st: *State = @ptrFromInt(cs.state_ptr);
                st.deinit();
                game.allocator.destroy(st);
            }
        }
        if (game.active_world.ecs_backend.hasComponent(entity, ControllerState)) {
            game.active_world.ecs_backend.removeComponent(entity, ControllerState);
        }
        log.info("Controller deinit", .{});
    }

    // ------------------------------------------------------------------
    // Public API (re-exported to game scripts as `pathfinder.Controller.*`)
    // ------------------------------------------------------------------

    /// Request navigation for `entity` towards `target` (world position).
    ///
    /// Resolves the entity's "from" node via its ClosestMovementNode
    /// component (fast path) or a live search (fallback), finds the
    /// closest node to `target`, and starts a Floyd-Warshall routed
    /// navigation. Returns a `Result` describing the outcome.
    ///
    /// `src` is the caller's `@src()` — kept for parity with
    /// WorkerController.apply() and for future audit logging.
    pub fn navigate(
        game: anytype,
        entity: anytype,
        target: Position,
        src: std.builtin.SourceLocation,
    ) Result {
        _ = src;
        const st = findState(game) orelse return .{ .rejected = .controller_not_setup };
        if (!st.nodes_registered) return .{ .deferred = .graph_not_built };

        const entity_id: u64 = @intCast(entity);

        // Cancel any prior route for this entity up front. Without this,
        // callers that replace an in-flight intent (e.g.
        // `07_production_system.navigateToEntity` swapping one target for
        // another) leak the previous pending ring slot + underlying pf
        // route whenever the new call returns anything other than
        // `.accepted` — most visibly on `.redundant`, where the old
        // bridge's `processArrivals` safety net used to drain the
        // orphaned entry. Making `navigate` idempotent here keeps the
        // controller the single source of truth regardless of the
        // caller's discipline.
        st.pf.cancel(entity_id);
        var i: usize = 0;
        while (i < st.pending_entities.items.len) {
            if (st.pending_entities.items[i] == entity_id) {
                st.removePending(i);
                break;
            }
            i += 1;
        }

        const pos = game.getPosition(entity);

        // Resolve `from` from the entity's LIVE position, not the cached
        // ClosestMovementNode. A stale CMN (e.g. the worker has moved
        // but NeedsClosestNode hasn't re-fired yet) points at a node
        // that Floyd-Warshall can't route from — the bridge hit this
        // as the "workstation between floors picks the wrong floor"
        // regression in #206. Using `findNearestNodeInState` with the
        // Y filter mirrors the bridge's successful behavior.
        //
        // A null result here means the entity is below every node the
        // Y filter considers — a persistent condition that won't
        // resolve without something else moving the entity. Treat as
        // `.rejected` so the dispatch drops the intent rather than
        // retrying forever. (to_node's null result is already
        // `.rejected` for the symmetric reason.)
        const from_node = findNearestNodeInState(st, pos.x, pos.y) orelse {
            return .{ .rejected = .no_nearby_node };
        };

        const to_node = findNearestNodeInState(st, target.x, target.y) orelse {
            return .{ .rejected = .no_nearby_node };
        };

        // One mover per entity: a graph walk replaces any in-flight
        // straight-line order.
        _ = st.direct_moves.swapRemove(entity_id);

        if (from_node == to_node) {
            // Worker and target resolve to the same node. The worker
            // isn't necessarily AT that node's world position yet —
            // the CMN-per-Euclidean-closest snap means the starting
            // position can still be tens of pixels away (e.g. spawn
            // position at (50, 0) with CMN at node (73, 0)). Before
            // returning `.redundant`, physically snap the worker onto
            // the node so callers doing a proximity check against the
            // real target (workstation / storage / etc.) don't spin
            // in a "too far from target, re-navigate, same node,
            // redundant" loop forever — #207. Matches the pathfinder's
            // own waypoint snap at ARRIVAL_THRESHOLD.
            const node_pos = st.pf.graph.getPosition(from_node);
            game.setPosition(entity, .{ .x = node_pos.x, .y = node_pos.y });
            // A redundant navigate IS an arrival — settle it so the
            // `pathfinder__arrived` event fires uniformly (subscribers
            // shouldn't care whether any walking was needed) and any
            // persisted `Navigating` from a prior order is cleared.
            settleArrival(game, st, entity_id, from_node);
            return .redundant;
        }

        const speed = if (game.active_world.ecs_backend.getComponent(entity, MovementSpeed)) |ms|
            ms.speed
        else
            DEFAULT_SPEED;

        const path = st.pf.navigate(entity_id, from_node, to_node, speed) catch |err| {
            log.err("navigate failed: entity={d} from={d} to={d}: {}", .{ entity_id, from_node, to_node, err });
            return .{ .rejected = .navigate_error };
        };
        if (path == null) return .{ .rejected = .no_path };

        if (!st.addPending(entity_id)) {
            // Allocation failure growing the ring. Cancel the route we
            // just started so we don't leak the entity in the underlying
            // pathfinder (it'd keep moving without the Controller
            // tracking it for arrivals). Caller sees `.deferred` and
            // retries next frame once memory frees up.
            st.pf.cancel(entity_id);
            return .{ .deferred = .pending_alloc_failed };
        }

        // Persist the order so a mid-walk save re-issues on load (the
        // live route above is transient state).
        game.active_world.ecs_backend.addComponent(entity, Navigating{
            .target_x = target.x,
            .target_y = target.y,
            .mode = .graph,
        });
        return .accepted;
    }

    /// Straight-line walk to a world position — the off-graph mover
    /// (ship-boundary hops, wander steps, anything the graph can't
    /// route). No routing: pure clamp-kinematics toward `target`,
    /// arrival at `DIRECT_ARRIVAL_RADIUS`, announced via
    /// `pathfinder__arrived` like any other walk. Speed comes from the
    /// entity's `MovementSpeed` (or the plugin default). Replaces the
    /// game-side raw `MovementTarget` writes from v3.
    pub fn moveTo(game: anytype, entity: anytype, target: Position) Result {
        const st = findState(game) orelse return .{ .rejected = .controller_not_setup };
        const entity_id: u64 = @intCast(entity);

        // One mover per entity: a direct order replaces any graph walk.
        st.pf.cancel(entity_id);
        var i: usize = 0;
        while (i < st.pending_entities.items.len) {
            if (st.pending_entities.items[i] == entity_id) {
                st.removePending(i);
                break;
            }
            i += 1;
        }

        const pos = game.getPosition(entity);
        const dx = target.x - pos.x;
        const dy = target.y - pos.y;
        if (@sqrt(dx * dx + dy * dy) < DIRECT_ARRIVAL_RADIUS) {
            settleArrival(game, st, entity_id, null);
            return .redundant;
        }

        const speed = if (game.active_world.ecs_backend.getComponent(entity, MovementSpeed)) |ms|
            ms.speed
        else
            DEFAULT_SPEED;

        st.direct_moves.put(st.allocator, entity_id, .{
            .target = target,
            .speed = speed,
        }) catch return .{ .deferred = .pending_alloc_failed };

        game.active_world.ecs_backend.addComponent(entity, Navigating{
            .target_x = target.x,
            .target_y = target.y,
            .mode = .direct,
        });
        return .accepted;
    }

    /// Cancel any active navigation for `entity`. Safe no-op if the
    /// entity wasn't navigating.
    ///
    /// Also drains the entity from the pending ring synchronously —
    /// otherwise a script calling `cancel` then `navigate` in the same
    /// tick (common with `07_production_system`'s `navigateToEntity`
    /// replacing an in-flight intent) would see the ring still holding
    /// the cancelled entry until the next `advance`'s
    /// `processArrivals`, eating a slot and re-adding a duplicate
    /// pending entry on the replacement `navigate`.
    pub fn cancel(game: anytype, entity: anytype) void {
        const st = findState(game) orelse return;
        const entity_id: u64 = @intCast(entity);
        st.pf.cancel(entity_id);
        _ = st.direct_moves.swapRemove(entity_id);
        // Drop the persisted order too — a cancelled walk must not
        // resurrect through the rehydration sweep next tick. No event:
        // the canceller knows what it did (cancel is a command, not a
        // surprise).
        {
            const Entity = @TypeOf(game.*).EntityType;
            const e: Entity = @intCast(entity_id);
            const ecs = &game.active_world.ecs_backend;
            if (ecs.entityExists(e)) ecs.removeComponent(e, Navigating);
        }
        // Swap-remove from the pending ring.
        var i: usize = 0;
        while (i < st.pending_entities.items.len) {
            if (st.pending_entities.items[i] == entity_id) {
                st.removePending(i);
                // Entity can appear only once (addPending de-dupes);
                // no need to keep scanning after a hit.
                return;
            }
            i += 1;
        }
    }

    /// Find the closest MovementNode BELOW (or at same Y as) the given
    /// position. Returns the node_id or `null` if no nodes are registered
    /// or none pass the Y filter.
    ///
    /// Y-filter rationale (from PR #206, preserved here): workers walk
    /// on top of their floor's nodes, so a node above the caller is on
    /// a higher floor and must not be picked as the CMN. Without the
    /// filter a workstation at Y=140 between floor-1 (Y=93) and floor-2
    /// (Y=186) picked the floor-2 node above it, which Floyd-Warshall
    /// couldn't reach via any stair chain.
    pub fn findClosestNode(game: anytype, position: Position) ?NodeId {
        const st = findState(game) orelse return null;
        return findNearestNodeInState(st, position.x, position.y);
    }

    /// Monotonic counter incremented every time the movement-node
    /// graph is (re)built. Game-side scripts compare this against
    /// a stored "last seen" value each tick — when it changes, the
    /// set of registered nodes has changed and any cached node
    /// assignments (`ClosestMovementNode`) should be re-resolved.
    ///
    /// Returns 0 when the pathfinder state isn't set up yet (pre-
    /// scene). Once the first build happens, the value becomes 1
    /// and increases monotonically from there.
    pub fn graphEpoch(game: anytype) u64 {
        const st = findState(game) orelse return 0;
        return st.graph_epoch;
    }

    /// Graph path-length between two game entities, via each entity's
    /// nearest movement node. Returns `null` when the controller isn't
    /// set up, either entity has no nearby node (Y-filtered, see
    /// `findClosestNode`), or no path exists between them.
    ///
    /// Intended for sibling-plugin callers (e.g. `production.Controller`'s
    /// scheduler) that need a CMN-graph-aware distance instead of the
    /// raw Euclidean `getPosition` delta. Uses Floyd-Warshall's
    /// pre-computed cost so each call is O(1) once the closest-node
    /// lookups (linear scan over registered MN nodes) finish — opportunity
    /// for entity-to-NodeId caching if this becomes a hot path.
    pub fn distance(game: anytype, from_entity: anytype, to_entity: anytype) ?f32 {
        const st = findState(game) orelse return null;
        // `getWorldPosition` (not `getPosition`) so parented
        // entities resolve to world-space coords and match the
        // graph's world-space movement nodes. The local-coords
        // path silently returned `null` for entities that lived
        // as children of workstations / rooms (e.g. a canteen's
        // FoodPacket Storage slots are children of the canteen
        // room) — `findNearestNodeForEntity` saw local coords
        // like `(27, 7)` against world-space nodes at `(229, 93)`
        // and rejected every candidate. Cursor flagged this on
        // PR #304; same pattern as `01_pathfinder_dispatch.zig`'s
        // explicit `getWorldPosition` use.
        const from_pos = game.getWorldPosition(from_entity);
        const to_pos = game.getWorldPosition(to_entity);

        // Both sides route through `findNearestNodeForEntity` — it's
        // now position-validated (#271), so moving workers can share
        // a cache without the "cached node drifts as the worker
        // walks across floors" failure mode the original interim
        // cache guarded against. See `State.nearest_node_cache` doc
        // for the validity contract.
        const from_id: u64 = @intCast(from_entity);
        const to_id: u64 = @intCast(to_entity);
        const from_node = findNearestNodeForEntity(st, from_id, from_pos.x, from_pos.y) orelse return null;
        const to_node = findNearestNodeForEntity(st, to_id, to_pos.x, to_pos.y) orelse return null;

        const d = st.pf.distance(from_node, to_node);
        if (d == types.INF) return null;
        return d;
    }

    /// Resolve the world-space position to use as a `NavigationIntent`'s
    /// target for `target_entity`. Reads the entity's `ClosestMovementNode`
    /// cache (preferred — already on-graph) and falls back to the entity's
    /// own world position when the cache hasn't been populated yet.
    ///
    /// Two pitfalls handled here that every call site has to get right
    /// (#310):
    ///   1. `cmn.node_entity != 0`. Prefab JSONC declares
    ///      `"ClosestMovementNode": {}`, leaving the field zero until the
    ///      pathfinder dispatch's `findClosestNode` populates it.
    ///      `getWorldPosition(0)` would resolve to whatever entity owns
    ///      ID 0 (the first scene entity — `background_sky` for
    ///      `flying-platform-labelle`'s `main`, at `(0, 768)`), routing
    ///      every fresh nav target toward the sky.
    ///   2. `getWorldPosition` (not `getPosition`) on both branches.
    ///      Storages / canteen seats / EOS slots are children of their
    ///      workstations or rooms, so `getPosition` returns local coords
    ///      that don't compare against world-space movement nodes. See
    ///      `movement.md` rule #4.
    ///
    /// Use this from any caller that builds a `NavigationIntent` for a
    /// world entity — currently `production`, `needs_machine`,
    /// `behavior_tree`, and `16_hunger_manager`.
    pub fn targetPosition(game: anytype, target_entity: anytype) Position {
        const Entity = @TypeOf(game.*).EntityType;
        if (game.active_world.ecs_backend.getComponent(target_entity, components.ClosestMovementNode)) |cmn| {
            if (cmn.node_entity != 0) {
                const node_entity: Entity = @intCast(cmn.node_entity);
                return game.getWorldPosition(node_entity);
            }
        }
        return game.getWorldPosition(target_entity);
    }

    /// Get the Controller's live state pointer. Intended for the
    /// plugin-dispatch script that translates the game's request-packet
    /// components (NavigationIntent, NeedsClosestNode) into Controller
    /// mutations — those components are game-owned, so the translation
    /// layer can't live inside the plugin. A `null` return means the
    /// singleton is not attached (e.g. between scenes or pre-setup).
    ///
    /// All graph-query helpers (`nodePosition`, `isNavigating`,
    /// `isReachable`, `nodeEntity`, graph slot iteration) are available
    /// on the `State` via its `pf` field; the dispatch script uses
    /// them to build closest-node queries without re-scanning the ECS.
    pub fn getState(game: anytype) ?*State {
        return findState(game);
    }

    /// Is this entity currently walking — via the graph OR a `moveTo`
    /// straight-line order? (v4: direct moves count; "is it walking"
    /// is the question every caller actually asks.)
    pub fn isNavigating(game: anytype, entity: anytype) bool {
        const st = findState(game) orelse return false;
        const entity_id: u64 = @intCast(entity);
        return st.isNavigating(entity_id) or st.direct_moves.contains(entity_id);
    }

    /// Is there ANY walkable route between the two entities' nearest
    /// nodes? The "can I even get there" gate (#48) — cheaper to ask
    /// than to `navigate` and watch it reject, and the single source
    /// of the reachability filter previously re-rolled game-side as
    /// `distance(...) != null`.
    pub fn reachable(game: anytype, from_entity: anytype, to_entity: anytype) bool {
        return distance(game, from_entity, to_entity) != null;
    }

    /// Walk-cost between two entities with the game-proven "nearest X"
    /// selector semantics (movement.md, single-sourced here in v4 —
    /// this absorbs the `entityDistance` helper that was triplicated
    /// across production/needs_machine/hunger call sites):
    ///   - graph built → true path cost, `inf` when disconnected
    ///     (an unreachable candidate must lose every distance-min
    ///     comparison, never win via a Euclidean fallback)
    ///   - graph not yet built → Euclidean (startup grace so finders
    ///     don't deadlock before the first node registers)
    /// World positions on both branches (parented entities compare in
    /// world space, movement.md rule #4).
    pub fn walkDistance(game: anytype, from_entity: anytype, to_entity: anytype) f32 {
        const st = findState(game) orelse return euclideanBetween(game, from_entity, to_entity);
        if (st.node_entities.count() == 0) {
            return euclideanBetween(game, from_entity, to_entity);
        }
        return distance(game, from_entity, to_entity) orelse std.math.inf(f32);
    }

    fn euclideanBetween(game: anytype, a: anytype, b: anytype) f32 {
        const pa = game.getWorldPosition(a);
        const pb = game.getWorldPosition(b);
        const dx = pa.x - pb.x;
        const dy = pa.y - pb.y;
        return @sqrt(dx * dx + dy * dy);
    }

    /// Re-resolve the entity's `ClosestMovementNode` immediately (v4:
    /// replaces the game-side `PendingRepath` marker + next-tick
    /// resolve round-trip — the plugin owns the CMN component, so
    /// there's nothing to defer). Removes the CMN when the entity is
    /// off-graph (no node within `MAX_NODE_SNAP_DISTANCE`).
    pub fn requestRepath(game: anytype, entity: anytype) void {
        const st = findState(game) orelse return;
        const entity_id: u64 = @intCast(entity);
        const ecs = &game.active_world.ecs_backend;
        const pos = game.getWorldPosition(entity);
        if (findNearestNodeForEntity(st, entity_id, pos.x, pos.y)) |nid| {
            const node_pos = st.pf.graph.getPosition(nid);
            const dx = node_pos.x - pos.x;
            const dy = node_pos.y - pos.y;
            ecs.addComponent(entity, ClosestMovementNode{
                .node_entity = st.node_entities.get(nid) orelse 0,
                .node_id = nid,
                .distance = @sqrt(dx * dx + dy * dy),
            });
        } else {
            ecs.removeComponent(entity, ClosestMovementNode);
        }
    }

    /// Number of slots the underlying graph has allocated. Useful for
    /// the dispatch script to detect whether the graph has been built.
    pub fn nodeCount(game: anytype) u32 {
        const st = findState(game) orelse return 0;
        return @intCast(st.node_entities.count());
    }

    /// Return the slice of entity ids currently navigating on the
    /// pending ring. Read-only — callers must NOT mutate.
    ///
    /// Intended for the room-deconstruction drain pass (#320), which
    /// needs to enumerate every in-flight `MovementPath` to count
    /// references to a `Retiring` `NodeId`. The slice is borrowed from a
    /// growable `ArrayListUnmanaged`, so it is invalidated by ANY call
    /// that mutates the ring: `advance` (drains arrivals), `cancel`
    /// (swap-removes), or `navigate` (appends — which may reallocate the
    /// backing buffer and move it). Consume it within the same tick,
    /// before any such call; never cache it across one.
    pub fn pendingEntities(game: anytype) []const u64 {
        const st = findState(game) orelse return &.{};
        return st.pending_entities.items;
    }

    /// Look up the active `MovementPath` for `entity`, or `null` if
    /// the entity isn't currently navigating. Read-only — the path's
    /// slices are owned by the pathfinder and freed when the
    /// navigation settles.
    ///
    /// Intended for the drain pass: scanning
    /// `path.node_path[path.current_index..path.len]` for a
    /// `Retiring` `NodeId` is the per-tick reference-count probe.
    pub fn getMovementPath(game: anytype, entity: anytype) ?*const movement_path.MovementPath {
        const st = findState(game) orelse return null;
        const entity_id: u64 = @intCast(entity);
        return st.pf.getPath(entity_id);
    }

    /// Return whether `node_id` has been tombstoned in the graph.
    /// Stale-node lookups return `true` (an out-of-bounds id is by
    /// definition not live).
    ///
    /// Intended for the `no_path_through_destroyed_node` caretaker
    /// rule.
    pub fn isNodeRemoved(game: anytype, node_id: NodeId) bool {
        const st = findState(game) orelse return true;
        return st.pf.graph.isRemoved(node_id);
    }

    /// Tombstone `node_id` in the underlying graph. The next call to
    /// `advance` will run `maybeRebuildGraph`, which already detects
    /// the staleness and rebuilds; what this accessor adds is the
    /// *same-tick* visibility — `isNodeRemoved` reports `true`
    /// immediately after the call, so a caretaker rule running later
    /// in the same tick (e.g. `no_path_through_destroyed_node`) can
    /// observe path/node mismatches that would otherwise be erased
    /// by the next-frame rebuild's `pending_entities.clearRetainingCapacity()`.
    ///
    /// Intended for the drain pass; pairs with `destroyEntity` on
    /// the matching `MovementNode` entity.
    pub fn removeNode(game: anytype, node_id: NodeId) void {
        const st = findState(game) orelse return;
        st.pf.removeNode(node_id);
        game.emit(.{ .pathfinder__node_removed = .{ .node_id = node_id } });
    }

    /// Per-frame advancement of in-flight navigations.
    ///
    /// Not auto-called — a one-line plugin-shipped script at
    /// `libs/pathfinder/scripts/playing/01_advance.zig` invokes this so
    /// tick ordering stays visible in `scripts/playing/`. The plugin
    /// block runs after the game's own `scripts/playing/*` block, so
    /// game scripts have already emitted this tick's `navigate` /
    /// `cancel` calls before `advance` sweeps the pathfinder.
    ///
    /// Responsibilities kept inside the plugin:
    ///   - lazy graph construction the first time MovementNodes appear
    ///   - stale-graph rebuild after scene swaps
    ///   - ticking the underlying Floyd-Warshall pathfinder
    ///   - arrival detection (drains the pending ring, fires the
    ///     plugin's arrival side-effects — the game's dispatch script
    ///     observes via `isNavigating` and reacts accordingly)
    pub fn advance(game: anytype, dt: f32) void {
        const st = findState(game) orelse return;

        maybeRebuildGraph(game, st);
        sweepCmnOnEpochChange(st, game);
        rehydrateNavigating(st, game);
        advanceNavigation(st, game, dt);
        advanceDirectMoves(st, game, dt);
        processArrivals(game, st);
        pruneNearestNodeCache(game, st);
    }

    /// Drop `nearest_node_cache` entries for entities that no longer
    /// exist (#493). The cache is keyed by entity id and populated
    /// lazily by `findNearestNodeForEntity` for EVERY entity that ever
    /// flows through `distance()` — workers, storages, items, beds,
    /// seats. Those entities churn constantly (items consumed, bandits
    /// killed, rooms demolished, corpses composted), but until now the
    /// cache was only ever cleared wholesale on a graph rebuild
    /// (`reset`) or, per-entry, on an OOM fallback in
    /// `findNearestNodeForEntity`. A long-running colony with heavy
    /// item/bandit churn therefore accumulated a dead entry per
    /// destroyed entity forever — unbounded growth that a graph rebuild
    /// only intermittently reclaims.
    ///
    /// The Controller can't observe arbitrary game-side `destroyEntity`
    /// calls across the module boundary (there's no central despawn
    /// hook the plugin subscribes to — `processArrivals` already relies
    /// on the same `entityExists` probe to drain the pending ring on
    /// entity death). So we sweep here once per tick: cheap relative to
    /// the navigation tick it rides alongside, and it bounds the cache
    /// to the live entity set rather than the high-water mark of every
    /// entity that ever queried a distance.
    ///
    /// Two-pass (collect dead keys, then remove) because removing from
    /// an `AutoHashMap` while iterating its `keyIterator` is unsafe.
    /// The scratch list is the State's persistent `cache_prune_scratch`
    /// (cleared, not freed, each tick) so steady state is zero-alloc.
    fn pruneNearestNodeCache(game: anytype, st: *State) void {
        if (st.nearest_node_cache.count() == 0) return;
        const ecs = &game.active_world.ecs_backend;
        const Entity = @TypeOf(game.*).EntityType;
        const AliveProbe = struct {
            ecs_ptr: @TypeOf(ecs),
            pub fn alive(self: @This(), entity_id: u64) bool {
                const entity: Entity = @intCast(entity_id);
                return self.ecs_ptr.entityExists(entity);
            }
        };
        pruneNearestNodeCacheBy(st, AliveProbe{ .ecs_ptr = ecs });
    }

    /// Explicitly (re)build the graph from MovementNode + MovementStair
    /// entities currently in the active world. Call after the host
    /// app has torn down and recreated the movement-node set (e.g.
    /// save/load). Idempotent: silently no-ops if the graph is already
    /// up to date with the current entity set.
    pub fn rebuildGraph(game: anytype) void {
        const st = findState(game) orelse return;
        st.reset(st.allocator);
        buildGraphIntoState(game, st);
    }

    // ------------------------------------------------------------------
    // Graph construction
    // ------------------------------------------------------------------

    fn buildGraphIntoState(game: anytype, st: *State) void {
        const ecs = &game.active_world.ecs_backend;
        var view = ecs.view(.{MovementNode}, .{});
        defer view.deinit();

        while (view.next()) |entity| {
            // World position, not local: movement nodes declared
            // inside a room prefab (`Room.movement_nodes`) end up as
            // children of the room entity, so `getPosition` returns
            // room-local coordinates. Queries (`findNearestNodeInState`
            // via `processPendingRepath`) feed `getWorldPosition`
            // for the storage/worker, so storing the graph at world
            // keeps both sides in the same frame. Previously the
            // frame mismatch caused topmost-shelf slots to fail
            // their 60-px arrival check after pathing to a node
            // whose local-vs-world delta exceeded the slack. See
            // the second half of #424.
            const pos = game.getWorldPosition(entity);
            const is_stair = ecs.hasComponent(entity, MovementStair);
            const node_id = st.pf.addNode(.{ .x = pos.x, .y = pos.y }, is_stair) catch |err| {
                log.err("addNode failed at ({d},{d}): {}", .{ pos.x, pos.y, err });
                continue;
            };
            // Reflect the pathfinder's assigned node_id back onto the
            // component so gizmos and other readers see the same ID
            // as the library's log output. Preserved from PR #206.
            if (ecs.getComponent(entity, MovementNode)) |mn| {
                mn.node_id = node_id;
            }
            const entity_id: u64 = @intCast(entity);
            st.node_entities.put(st.allocator, node_id, entity_id) catch |err| {
                log.err("failed to track node {d}: {}", .{ node_id, err });
            };
        }

        st.nodes_registered = st.node_entities.count() > 0;
        if (st.nodes_registered) {
            log.info("graph built: {d} nodes (Floyd-Warshall)", .{st.node_entities.count()});
        }
        // Bump the rebuild epoch so consumers know cached node
        // assignments went stale — see #424. Bumped even when no nodes
        // ended up registered, so a transition from "had nodes" → "all
        // nodes removed" still counts as a change observers can react
        // to. The event is the push twin of the `graphEpoch()` poll
        // (v4); the plugin's own CMN sweep keys off the same counter.
        st.graph_epoch += 1;
        game.emit(.{ .pathfinder__graph_rebuilt = .{ .epoch = st.graph_epoch } });
    }

    fn hasMovementNodes(game: anytype) bool {
        var view = game.active_world.ecs_backend.view(.{MovementNode}, .{});
        defer view.deinit();
        return view.next() != null;
    }

    fn isGraphStale(game: anytype, st: *State) bool {
        if (st.node_entities.count() == 0) return false;
        const ecs = &game.active_world.ecs_backend;
        const first_id = st.node_entities.values()[0];
        const Entity = @TypeOf(game.*).EntityType;
        const first_entity: Entity = @intCast(first_id);
        return !ecs.entityExists(first_entity);
    }

    fn maybeRebuildGraph(game: anytype, st: *State) void {
        const empty_but_populated = !st.nodes_registered and hasMovementNodes(game);
        const stale = st.nodes_registered and isGraphStale(game, st);
        if (!empty_but_populated and !stale) return;

        st.reset(st.allocator);
        buildGraphIntoState(game, st);
    }

    // ------------------------------------------------------------------
    // Movement tick + arrivals
    // ------------------------------------------------------------------

    fn advanceNavigation(st: *State, game: anytype, dt: f32) void {
        var ctx = GameCtx(@TypeOf(game)){ .game = game, .st = st };
        st.pf.tick(&ctx, dt);
    }

    /// Walk every in-flight `moveTo` straight-line order: clamp-move
    /// toward the target, settle on arrival. Same kinematics as the
    /// game-side walker this absorbed (min(speed·dt, dist), no
    /// overshoot, `DIRECT_ARRIVAL_RADIUS` arrival).
    fn advanceDirectMoves(st: *State, game: anytype, dt: f32) void {
        if (st.direct_moves.count() == 0) return;
        const Entity = @TypeOf(game.*).EntityType;
        const ecs = &game.active_world.ecs_backend;

        // Settles are collected and processed after the iteration —
        // `settleArrival` mutates components and `fetchSwapRemove`
        // reorders the map, neither safe mid-iteration.
        var settled: std.ArrayListUnmanaged(u64) = .empty;
        defer settled.deinit(st.allocator);

        for (st.direct_moves.keys(), st.direct_moves.values()) |entity_id, dm| {
            const entity: Entity = @intCast(entity_id);
            if (!ecs.entityExists(entity)) {
                settled.append(st.allocator, entity_id) catch break;
                continue;
            }
            const pos = game.getPosition(entity);
            switch (directStep(pos, dm.target, dm.speed, dt)) {
                .arrived => settled.append(st.allocator, entity_id) catch break,
                .move => |next| game.setPosition(entity, next),
            }
        }

        for (settled.items) |entity_id| {
            _ = st.direct_moves.swapRemove(entity_id);
            const entity: Entity = @intCast(entity_id);
            if (ecs.entityExists(entity)) {
                settleArrival(game, st, entity_id, null);
            }
        }
    }

    /// Re-issue persisted walk orders the live tracker doesn't know
    /// about. The tracker state (`ControllerState`) is `.transient`
    /// while `Navigating` is `.saveable` — after a load, entities
    /// carry their orders but the pathfinder has no routes for them.
    /// A re-issue that no longer resolves (graph changed under the
    /// save) settles as a failure so the order can't dangle forever.
    fn rehydrateNavigating(st: *State, game: anytype) void {
        if (!st.nodes_registered) return;
        const Entity = @TypeOf(game.*).EntityType;
        const ecs = &game.active_world.ecs_backend;

        var orphans: std.ArrayListUnmanaged(u64) = .empty;
        defer orphans.deinit(st.allocator);
        {
            var view = ecs.view(.{Navigating}, .{});
            defer view.deinit();
            while (view.next()) |entity| {
                const id: u64 = @intCast(entity);
                if (st.pf.isNavigating(id)) continue;
                if (st.direct_moves.contains(id)) continue;
                orphans.append(st.allocator, id) catch break;
            }
        }

        for (orphans.items) |id| {
            const entity: Entity = @intCast(id);
            const nav = ecs.getComponent(entity, Navigating) orelse continue;
            const target = Position{ .x = nav.target_x, .y = nav.target_y };
            switch (nav.mode) {
                .direct => {
                    _ = moveTo(game, entity, target);
                },
                .graph => switch (navigate(game, entity, target, @src())) {
                    .accepted, .redundant => {},
                    // Deferred is transient (graph mid-rebuild) — keep the
                    // order, retry next tick.
                    .deferred => {},
                    .rejected => |r| settleFailed(game, id, switch (r) {
                        .no_path => .no_path,
                        .no_nearby_node => .no_nearby_node,
                        else => .navigate_error,
                    }),
                },
            }
        }
    }

    /// Epoch-change CMN invalidation (moved in from the game-side
    /// dispatch in v4): when the graph is rebuilt, every cached
    /// `ClosestMovementNode` may point at a node that no longer exists
    /// or is no longer optimal. Drop them all; arrivals and
    /// `requestRepath` re-resolve lazily.
    fn sweepCmnOnEpochChange(st: *State, game: anytype) void {
        if (st.graph_epoch == st.last_cmn_epoch) return;
        const Entity = @TypeOf(game.*).EntityType;
        const ecs = &game.active_world.ecs_backend;

        var holders: std.ArrayListUnmanaged(u64) = .empty;
        defer holders.deinit(st.allocator);
        var collected_all = true;
        {
            var view = ecs.view(.{ClosestMovementNode}, .{});
            defer view.deinit();
            while (view.next()) |entity| {
                holders.append(st.allocator, @intCast(entity)) catch {
                    // OOM: don't advance the epoch marker — next tick
                    // re-runs the whole sweep.
                    collected_all = false;
                    break;
                };
            }
        }
        for (holders.items) |id| {
            const entity: Entity = @intCast(id);
            ecs.removeComponent(entity, ClosestMovementNode);
        }
        if (collected_all) st.last_cmn_epoch = st.graph_epoch;
    }

    /// Drain the pending ring of entities whose pathfinder navigation
    /// has settled (arrived, destroyed, or cancelled externally).
    /// Removes them from the ring so `isNavigating` returns false.
    /// Pure bookkeeping in v4 — the observable side effects (the
    /// `pathfinder__arrived`/`navigation_failed` events, CMN refresh,
    /// `Navigating` removal) fire from the tick's settle callbacks;
    /// destroyed entities need none (their components die with them).
    fn processArrivals(game: anytype, st: *State) void {
        const ecs = &game.active_world.ecs_backend;
        const Entity = @TypeOf(game.*).EntityType;

        var i: usize = 0;
        while (i < st.pending_entities.items.len) {
            const entity_id = st.pending_entities.items[i];
            const entity: Entity = @intCast(entity_id);

            if (!ecs.entityExists(entity)) {
                st.pf.cancel(entity_id);
                st.removePending(i);
                continue;
            }

            if (!st.pf.isNavigating(entity_id)) {
                // pathfinder dropped the entity (arrived, graph
                // invalidated, or explicit cancel). Just drain the ring
                // — the dispatch script observes the state change.
                st.removePending(i);
            } else {
                i += 1;
            }
        }
    }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    fn findStateEntity(game: anytype) ?@TypeOf(game.*).EntityType {
        var view = game.active_world.ecs_backend.view(.{ControllerState}, .{});
        defer view.deinit();
        return view.next();
    }

    fn findState(game: anytype) ?*State {
        const entity = findStateEntity(game) orelse return null;
        const cs = game.active_world.ecs_backend.getComponent(entity, ControllerState) orelse return null;
        if (cs.state_ptr == 0) return null;
        return @ptrFromInt(cs.state_ptr);
    }
};

// ============================================================================
// Shared helpers
// ============================================================================

/// Prune `nearest_node_cache` entries whose entity is no longer alive,
/// as judged by `probe.alive(entity_id) bool` (#493). Two-pass: collect
/// the dead keys into the State's persistent `cache_prune_scratch` (an
/// `AutoHashMap`'s `keyIterator` is invalidated by `remove`), then drop
/// them. Steady-state zero-alloc — the scratch is cleared, not freed.
///
/// Extracted from `Controller.pruneNearestNodeCache` so the prune logic
/// is unit-testable against a synthetic `State` + predicate without a
/// live game/ECS backend (see `tests/controller_cache_test.zig`).
pub fn pruneNearestNodeCacheBy(st: *State, probe: anytype) void {
    st.cache_prune_scratch.clearRetainingCapacity();
    var it = st.nearest_node_cache.keyIterator();
    while (it.next()) |key_ptr| {
        if (!probe.alive(key_ptr.*)) {
            // OOM here just defers the prune to a later tick — the dead
            // entry stays one more frame, never a correctness issue (a
            // stale entry is only ever read after an `entityExists`-gated
            // lookup re-validates the entity in the caller's path).
            st.cache_prune_scratch.append(st.allocator, key_ptr.*) catch break;
        }
    }
    for (st.cache_prune_scratch.items) |dead_id| {
        _ = st.nearest_node_cache.remove(dead_id);
    }
}

/// Entity-keyed wrapper over `findNearestNodeInState` that memoises
/// per-entity lookups across calls. Correct for both stationary and
/// moving entities — see `State.nearest_node_cache` for the
/// validity contract. On a cache miss (no entry OR entry exceeded
/// drift bounds) we rescan and overwrite so the cache acts as a
/// position-keyed memoizer rather than a one-shot initializer.
fn findNearestNodeForEntity(st: *State, entity_id: u64, x: f32, y: f32) ?NodeId {
    if (st.nearest_node_cache.get(entity_id)) |cached| {
        if (cachedNearestStillValid(cached, x, y)) return cached.node_id;
    }
    const nid = findNearestNodeInState(st, x, y) orelse return null;
    const node_pos = st.pf.graph.getPosition(nid);
    // On `put` OOM we drop the old entry explicitly so subsequent
    // calls either succeed (re-put with fresh data) or cache-miss
    // into a rescan, rather than keep validating against a stale
    // record we just decided was wrong.
    st.nearest_node_cache.put(entity_id, .{
        .node_id = nid,
        .cached_x = x,
        .cached_y = y,
        .cached_node_y = node_pos.y,
    }) catch {
        _ = st.nearest_node_cache.remove(entity_id);
    };
    return nid;
}

/// Is `cached` still the best answer for a query at (x, y)? Two
/// independent conditions must hold:
///
///   1. The cached node still passes the Y-filter applied by
///      `findNearestNodeInState` at the NEW entity Y — i.e.
///      `cached_node_y <= y + Y_FILTER_EPS`. This is an exact
///      re-application of the filter, not a heuristic, so floor
///      changes are caught precisely instead of approximated by a
///      per-entity Y-drift bound.
///
///   2. The entity has drifted less than `CACHE_POS_THRESHOLD` in
///      the plane since the cached position, so a sibling node on
///      the same floor can't plausibly have overtaken the cached
///      winner (see the 15-px ≈ half-min-node-spacing comment on
///      `CACHE_POS_THRESHOLD`).
///
/// Kept pure so the threshold logic is unit-testable without a live
/// `State` (see `tests/controller_cache_test.zig`).
pub fn cachedNearestStillValid(cached: CachedNearest, x: f32, y: f32) bool {
    if (cached.cached_node_y > y + Y_FILTER_EPS) return false;
    const dx = x - cached.cached_x;
    const dy = y - cached.cached_y;
    return dx * dx + dy * dy < CACHE_POS_THRESHOLD_SQ;
}

pub fn findNearestNodeInState(st: *State, x: f32, y: f32) ?NodeId {
    const slots = st.pf.graph.totalSlots();
    if (slots == 0) return null;

    var best: ?NodeId = null;
    var best_dist: f32 = std.math.inf(f32);
    for (0..slots) |i| {
        const nid: NodeId = @intCast(i);
        if (st.pf.graph.isRemoved(nid)) continue;
        const npos = st.pf.graph.getPosition(nid);
        if (npos.y > y + Y_FILTER_EPS) continue; // only at-or-below entity
        const dx = npos.x - x;
        const dy = npos.y - y;
        const dist = @sqrt(dx * dx + dy * dy);
        if (dist < best_dist) {
            best_dist = dist;
            best = nid;
        }
    }
    // Reject snaps farther than MAX_NODE_SNAP_DISTANCE — see the
    // constant's doc comment. Treats entities placed too far from
    // any walkable node as off-graph so `distance` and `navigate`
    // can't silently route through a far-away node.
    if (best_dist > MAX_NODE_SNAP_DISTANCE) return null;
    return best;
}

/// One straight-line walk step: arrived when within
/// `DIRECT_ARRIVAL_RADIUS`, else the next position clamped to
/// `min(speed·dt, remaining)` so the walker never overshoots. Pure so
/// the kinematics are unit-testable without a game harness (the same
/// extraction the game-side walker this absorbed had).
pub const DirectStep = union(enum) {
    arrived,
    move: Position,
};

pub fn directStep(pos: Position, target: Position, speed: f32, dt: f32) DirectStep {
    const dx = target.x - pos.x;
    const dy = target.y - pos.y;
    const dist = @sqrt(dx * dx + dy * dy);
    if (dist < DIRECT_ARRIVAL_RADIUS) return .arrived;
    const move_dist = @min(speed * dt, dist);
    return .{ .move = .{
        .x = pos.x + (dx / dist) * move_dist,
        .y = pos.y + (dy / dist) * move_dist,
    } };
}

/// Settle an arrived walk: refresh the entity's CMN to where it now
/// stands, drop the persisted `Navigating` order, and announce via the
/// `pathfinder__arrived` game event (buffered; subscribers see it at
/// end-of-frame dispatch). `goal_node` is null for direct (off-graph)
/// arrivals — the CMN then re-resolves from the arrival position.
fn settleArrival(game: anytype, st: *State, entity_id: u64, goal_node: ?NodeId) void {
    const Entity = @TypeOf(game.*).EntityType;
    const entity: Entity = @intCast(entity_id);
    const ecs = &game.active_world.ecs_backend;
    if (!ecs.entityExists(entity)) return;

    ecs.removeComponent(entity, Navigating);

    // CMN refresh replaces the old game-side arrival → NeedsClosestNode
    // marker → next-tick resolve round-trip: the plugin owns the CMN
    // component, so resolve it here and now.
    var node_entity: u64 = 0;
    const resolved: ?NodeId = goal_node orelse blk: {
        const pos = game.getWorldPosition(entity);
        break :blk findNearestNodeForEntity(st, entity_id, pos.x, pos.y);
    };
    if (resolved) |nid| {
        node_entity = st.node_entities.get(nid) orelse 0;
        ecs.addComponent(entity, ClosestMovementNode{
            .node_entity = node_entity,
            .node_id = nid,
            .distance = 0,
        });
    }

    game.emit(.{ .pathfinder__arrived = .{
        .entity = entity_id,
        .node_entity = node_entity,
    } });
}

/// Settle a failed walk: drop the persisted order and announce. The
/// caller that issued the walk learns the outcome by subscribing to
/// `pathfinder__navigation_failed` (or by re-querying) — commands
/// return acceptance, not effects (RFC-packs §6).
fn settleFailed(game: anytype, entity_id: u64, reason: FailReason) void {
    const Entity = @TypeOf(game.*).EntityType;
    const entity: Entity = @intCast(entity_id);
    const ecs = &game.active_world.ecs_backend;
    if (ecs.entityExists(entity)) {
        ecs.removeComponent(entity, Navigating);
    }
    game.emit(.{ .pathfinder__navigation_failed = .{
        .entity = entity_id,
        .reason = reason,
    } });
}

/// Thin bridge exposing `getEntityPosition` / `moveEntity` to the
/// pathfinder tick loop, plus the v4 settle callbacks that let the
/// tick announce arrivals/failures as game events. Parameterized on
/// the game's concrete type so the Entity cast and `getPosition` /
/// `setPosition` lookups are monomorphized per call site.
fn GameCtx(comptime GameType: type) type {
    return struct {
        game: GameType,
        st: *State,

        pub fn onArrived(self: *@This(), entity_id: u64, goal_node: NodeId) void {
            settleArrival(self.game, self.st, entity_id, goal_node);
        }

        pub fn onPathInvalidated(self: *@This(), entity_id: u64, goal_node: NodeId) void {
            _ = goal_node;
            settleFailed(self.game, entity_id, .path_invalidated);
        }

        pub fn getEntityPosition(self: *@This(), entity_id: u64) ?Position {
            const Entity = @TypeOf(self.game.*).EntityType;
            const entity: Entity = @intCast(entity_id);
            if (!self.game.active_world.ecs_backend.entityExists(entity)) return null;
            const pos = self.game.getPosition(entity);
            return .{ .x = pos.x, .y = pos.y };
        }

        pub fn moveEntity(self: *@This(), entity_id: u64, dx: f32, dy: f32) void {
            const Entity = @TypeOf(self.game.*).EntityType;
            const entity: Entity = @intCast(entity_id);
            if (!self.game.active_world.ecs_backend.entityExists(entity)) return;
            // CONTRACT CHANGE from the deleted 01_pathfinder_bridge.zig:
            // the bridge's equivalent here explicitly skipped movement
            // for entities with a `Fighting` component (game-side
            // safety net so a worker yanked into combat didn't keep
            // sliding along its in-flight path). The Controller can't
            // consult game components across the Zig module boundary,
            // so the onus moved to callers: every site that adds a
            // game-side "this entity can't move right now" marker
            // (Fighting, Stunned, etc.) must call `Controller.cancel`
            // at the same time. `12_fight_resolver` does this today
            // (see its `interruptWorker` + explicit `cancelNavigation`
            // on the bandit side). Any future equivalent must follow
            // the same pattern; a generic "pause movement for N
            // entities" hook is tracked as a follow-up.
            const pos = self.game.getPosition(entity);
            self.game.setPosition(entity, .{ .x = pos.x + dx, .y = pos.y + dy });
        }
    };
}
