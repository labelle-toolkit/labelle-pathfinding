//! labelle-pathfinding Hook System
//!
//! A type-safe, comptime-based hook/event system for labelle-pathfinding.
//! Compatible with labelle-engine's hook system patterns.
//!
//! ## Overview
//!
//! The hook system allows games to observe pathfinding lifecycle events
//! (path found, no path, search started, etc.) with zero runtime overhead.
//!
//! ## Usage
//!
//! Define a hook handler struct with functions matching hook names:
//!
//! ```zig
//! const MyPathHooks = struct {
//!     pub fn path_found(payload: pathfinding.hooks.HookPayload) void {
//!         const info = payload.path_found;
//!         std.log.info("Path found! Cost: {d}, nodes: {d}", .{
//!             info.cost, info.path_length,
//!         });
//!     }
//!
//!     pub fn no_path_found(payload: pathfinding.hooks.HookPayload) void {
//!         const info = payload.no_path_found;
//!         std.log.info("No path from {d} to {d}", .{info.source, info.dest});
//!     }
//! };
//!
//! // Create a dispatcher
//! const Dispatcher = pathfinding.hooks.HookDispatcher(MyPathHooks);
//!
//! // Use AStarWithHooks with the dispatcher
//! var astar = pathfinding.AStarWithHooks(Dispatcher).init(allocator);
//! ```
//!
//! ## Available Hooks
//!
//! ### Algorithm Hooks (A*, Floyd-Warshall)
//! - `path_requested` - When pathfinding is initiated
//! - `path_found` - When a valid path is discovered
//! - `no_path_found` - When no path exists between nodes
//! - `node_visited` - When a node is visited during search (for debugging/visualization)
//! - `search_complete` - When the search algorithm finishes (success or failure)
//!
//! ### Stair/Movement Hooks (PathfindingEngine)
//! - `stair_enter` - When an entity enters a stair
//! - `stair_exit` - When an entity exits a stair
//! - `stair_wait` - When an entity starts waiting for a stair (blocked by traffic)

const std = @import("std");

/// Vertical direction for stair traversal
pub const VerticalDirection = @import("types.zig").VerticalDirection;

/// Built-in hooks for pathfinding lifecycle events.
/// Games can register handlers for any of these hooks.
pub const PathfindingHook = enum {
    // ========================================================================
    // Algorithm hooks
    // ========================================================================

    /// Fired when pathfinding is requested between two nodes
    path_requested,

    /// Fired when a valid path is found
    path_found,

    /// Fired when no path exists between source and destination
    no_path_found,

    /// Fired when a node is visited during the search (for visualization/debugging)
    node_visited,

    /// Fired when the search algorithm completes (success or failure)
    search_complete,

    // ========================================================================
    // Stair/movement hooks (emitted by PathfindingEngine)
    // ========================================================================

    /// Fired when an entity enters a stair
    stair_enter,

    /// Fired when an entity exits a stair
    stair_exit,

    /// Fired when an entity starts waiting for a stair (blocked by traffic)
    stair_wait,
};

/// Information about a path request
pub const PathRequestInfo = struct {
    source: u32,
    dest: u32,
};

/// Information about a found path
pub const PathFoundInfo = struct {
    source: u32,
    dest: u32,
    cost: u64,
    path_length: usize,
};

/// Information about a failed path search
pub const NoPathFoundInfo = struct {
    source: u32,
    dest: u32,
    nodes_explored: u32,
};

/// Information about a visited node (for debugging/visualization)
pub const NodeVisitedInfo = struct {
    node: u32,
    g_score: u64,
    f_score: f32,
    from_node: ?u32,
};

/// Information about search completion
pub const SearchCompleteInfo = struct {
    source: u32,
    dest: u32,
    success: bool,
    nodes_explored: u32,
    path_length: usize,
    cost: ?u64,
};

/// Information about a stair enter event
pub const StairEnterInfo = struct {
    /// The entity entering the stair
    entity: u64,
    /// The stair node being entered
    stair_node: u32,
    /// Direction of travel
    direction: VerticalDirection,
    /// The node the entity is coming from
    from_node: u32,
    /// The node the entity is going to
    to_node: u32,
};

/// Information about a stair exit event
pub const StairExitInfo = struct {
    /// The entity exiting the stair
    entity: u64,
    /// The stair node being exited
    stair_node: u32,
    /// The node the entity arrived at
    arrived_at: u32,
};

/// Information about a stair wait event (entity blocked by traffic)
pub const StairWaitInfo = struct {
    /// The entity waiting
    entity: u64,
    /// The stair node the entity is waiting for
    stair_node: u32,
    /// Direction the entity wants to travel
    direction: VerticalDirection,
    /// The node the entity is waiting at
    waiting_at: u32,
    /// Current number of users on the stair
    current_users: u32,
};

/// Type-safe payload union for pathfinding hooks.
/// Each hook type has its corresponding payload type.
pub const HookPayload = union(PathfindingHook) {
    path_requested: PathRequestInfo,
    path_found: PathFoundInfo,
    no_path_found: NoPathFoundInfo,
    node_visited: NodeVisitedInfo,
    search_complete: SearchCompleteInfo,
    stair_enter: StairEnterInfo,
    stair_exit: StairExitInfo,
    stair_wait: StairWaitInfo,
};

/// Creates a hook dispatcher from a comptime hook map.
///
/// The HookMap should be a struct type where each public declaration is a
/// function matching the signature for that hook.
///
/// Example:
/// ```zig
/// const MyHooks = struct {
///     pub fn path_found(payload: pathfinding.hooks.HookPayload) void {
///         const info = payload.path_found;
///         std.log.info("Path found!", .{});
///     }
/// };
///
/// const Dispatcher = pathfinding.hooks.HookDispatcher(MyHooks);
/// Dispatcher.emit(.{ .path_found = .{ ... } });
/// ```
pub fn HookDispatcher(comptime HookMap: type) type {
    return struct {
        const Self = @This();

        /// The hook enum type this dispatcher handles.
        pub const Hook = PathfindingHook;

        /// The payload union type this dispatcher handles.
        pub const Payload = HookPayload;

        /// The hook handler map type.
        pub const Handlers = HookMap;

        /// Emit a hook event. Resolved entirely at comptime - no runtime overhead.
        ///
        /// If no handler is registered for the hook, this is a no-op.
        pub inline fn emit(payload: HookPayload) void {
            switch (payload) {
                inline else => |_, tag| {
                    const hook_name = @tagName(tag);
                    if (@hasDecl(HookMap, hook_name)) {
                        const handler = @field(HookMap, hook_name);
                        handler(payload);
                    }
                },
            }
        }

        /// Check at comptime if a hook has a handler registered.
        pub fn hasHandler(comptime hook: PathfindingHook) bool {
            return @hasDecl(HookMap, @tagName(hook));
        }

        /// Get the number of hooks that have handlers registered.
        pub fn handlerCount() comptime_int {
            var count: comptime_int = 0;
            for (std.enums.values(PathfindingHook)) |hook| {
                if (@hasDecl(HookMap, @tagName(hook))) {
                    count += 1;
                }
            }
            return count;
        }
    };
}

/// An empty hook dispatcher with no handlers.
/// Useful as a default when no hooks are needed.
pub const EmptyDispatcher = HookDispatcher(struct {});

/// Merges multiple hook handler structs into one composite dispatcher.
/// When a hook is emitted, all matching handlers from all structs are called in order.
///
/// Example:
/// ```zig
/// const GameHooks = struct {
///     pub fn path_found(payload: pathfinding.hooks.HookPayload) void {
///         std.log.info("Game: path found!", .{});
///     }
/// };
///
/// const AnalyticsHooks = struct {
///     pub fn path_found(payload: pathfinding.hooks.HookPayload) void {
///         // Track analytics
///     }
/// };
///
/// // Merge - both handlers will be called
/// const AllHooks = pathfinding.hooks.MergePathfindingHooks(.{ GameHooks, AnalyticsHooks });
/// ```
pub fn MergePathfindingHooks(comptime handler_structs: anytype) type {
    return struct {
        const Self = @This();

        /// The hook enum type this dispatcher handles.
        pub const Hook = PathfindingHook;

        /// The payload union type this dispatcher handles.
        pub const Payload = HookPayload;

        /// Emit a hook event to all registered handlers.
        /// Handlers are called in the order the structs appear in handler_structs.
        pub inline fn emit(payload: HookPayload) void {
            switch (payload) {
                inline else => |_, tag| {
                    const hook_name = @tagName(tag);
                    inline for (handler_structs) |H| {
                        if (@hasDecl(H, hook_name)) {
                            const handler = @field(H, hook_name);
                            handler(payload);
                        }
                    }
                },
            }
        }

        /// Check at comptime if any handler struct has a handler for this hook.
        pub fn hasHandler(comptime hook: PathfindingHook) bool {
            inline for (handler_structs) |H| {
                if (@hasDecl(H, @tagName(hook))) {
                    return true;
                }
            }
            return false;
        }

        /// Get the number of unique hooks that have at least one handler registered.
        pub fn handlerCount() comptime_int {
            var count: comptime_int = 0;
            for (std.enums.values(PathfindingHook)) |hook| {
                if (hasHandler(hook)) {
                    count += 1;
                }
            }
            return count;
        }
    };
}
