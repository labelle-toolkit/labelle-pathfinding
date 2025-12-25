const std = @import("std");
const zspec = @import("zspec");
const pathfinding = @import("labelle_pathfinding");

const expect = zspec.expect;
const hooks = pathfinding.hooks;

pub const HooksSpec = struct {
    pub const @"HookDispatcher" = struct {
        test "emits to registered handlers" {
            const TestHooks = struct {
                var path_found_count: u32 = 0;
                var last_cost: u64 = 0;

                pub fn path_found(payload: hooks.HookPayload) void {
                    const info = payload.path_found;
                    path_found_count += 1;
                    last_cost = info.cost;
                }
            };

            const Dispatcher = hooks.HookDispatcher(TestHooks);

            // Reset state
            TestHooks.path_found_count = 0;
            TestHooks.last_cost = 0;

            // Emit event
            Dispatcher.emit(.{ .path_found = .{
                .source = 1,
                .dest = 10,
                .cost = 42,
                .path_length = 5,
            } });

            try expect.equal(TestHooks.path_found_count, 1);
            try expect.equal(TestHooks.last_cost, 42);
        }

        test "ignores unhandled hooks" {
            const TestHooks = struct {
                var count: u32 = 0;

                pub fn path_found(_: hooks.HookPayload) void {
                    count += 1;
                }
                // no_path_found is not handled
            };

            const Dispatcher = hooks.HookDispatcher(TestHooks);

            TestHooks.count = 0;

            // This should not crash even though no_path_found is not handled
            Dispatcher.emit(.{ .no_path_found = .{
                .source = 1,
                .dest = 10,
                .nodes_explored = 50,
            } });

            try expect.equal(TestHooks.count, 0);
        }

        test "hasHandler returns correct values" {
            const TestHooks = struct {
                pub fn path_found(_: hooks.HookPayload) void {}
                pub fn search_complete(_: hooks.HookPayload) void {}
            };

            const Dispatcher = hooks.HookDispatcher(TestHooks);

            try expect.toBeTrue(Dispatcher.hasHandler(.path_found));
            try expect.toBeTrue(Dispatcher.hasHandler(.search_complete));
            try expect.toBeFalse(Dispatcher.hasHandler(.no_path_found));
            try expect.toBeFalse(Dispatcher.hasHandler(.node_visited));
        }

        test "handlerCount returns correct count" {
            const TestHooks = struct {
                pub fn path_found(_: hooks.HookPayload) void {}
                pub fn no_path_found(_: hooks.HookPayload) void {}
                pub fn search_complete(_: hooks.HookPayload) void {}
            };

            const Dispatcher = hooks.HookDispatcher(TestHooks);

            try expect.equal(Dispatcher.handlerCount(), 3);
        }
    };

    pub const @"EmptyDispatcher" = struct {
        test "has no handlers" {
            try expect.equal(hooks.EmptyDispatcher.handlerCount(), 0);
            try expect.toBeFalse(hooks.EmptyDispatcher.hasHandler(.path_found));
        }
    };

    pub const @"MergePathfindingHooks" = struct {
        test "calls all handlers" {
            const Hooks1 = struct {
                var called: bool = false;

                pub fn search_complete(_: hooks.HookPayload) void {
                    called = true;
                }
            };

            const Hooks2 = struct {
                var called: bool = false;

                pub fn search_complete(_: hooks.HookPayload) void {
                    called = true;
                }
            };

            const Merged = hooks.MergePathfindingHooks(.{ Hooks1, Hooks2 });

            // Reset state
            Hooks1.called = false;
            Hooks2.called = false;

            Merged.emit(.{ .search_complete = .{
                .source = 1,
                .dest = 10,
                .success = true,
                .nodes_explored = 25,
                .path_length = 5,
                .cost = 42,
            } });

            try expect.toBeTrue(Hooks1.called);
            try expect.toBeTrue(Hooks2.called);
        }
    };

    pub const @"Stair hooks" = struct {
        test "stair_enter hook has correct payload structure" {
            const TestHooks = struct {
                var called: bool = false;
                var last_entity: u64 = 0;
                var last_stair_node: u32 = 0;
                var last_direction: hooks.VerticalDirection = .up;

                pub fn stair_enter(payload: hooks.HookPayload) void {
                    const info = payload.stair_enter;
                    called = true;
                    last_entity = info.entity;
                    last_stair_node = info.stair_node;
                    last_direction = info.direction;
                }
            };

            const Dispatcher = hooks.HookDispatcher(TestHooks);

            TestHooks.called = false;

            Dispatcher.emit(.{ .stair_enter = .{
                .entity = 42,
                .stair_node = 5,
                .direction = .down,
                .from_node = 4,
                .to_node = 6,
            } });

            try expect.toBeTrue(TestHooks.called);
            try expect.equal(TestHooks.last_entity, 42);
            try expect.equal(TestHooks.last_stair_node, 5);
            try expect.equal(TestHooks.last_direction, .down);
        }

        test "stair_exit hook has correct payload structure" {
            const TestHooks = struct {
                var called: bool = false;
                var last_arrived_at: u32 = 0;

                pub fn stair_exit(payload: hooks.HookPayload) void {
                    const info = payload.stair_exit;
                    called = true;
                    last_arrived_at = info.arrived_at;
                }
            };

            const Dispatcher = hooks.HookDispatcher(TestHooks);

            TestHooks.called = false;

            Dispatcher.emit(.{ .stair_exit = .{
                .entity = 42,
                .stair_node = 5,
                .arrived_at = 7,
            } });

            try expect.toBeTrue(TestHooks.called);
            try expect.equal(TestHooks.last_arrived_at, 7);
        }

        test "stair_wait hook has correct payload structure" {
            const TestHooks = struct {
                var called: bool = false;
                var last_current_users: u32 = 0;

                pub fn stair_wait(payload: hooks.HookPayload) void {
                    const info = payload.stair_wait;
                    called = true;
                    last_current_users = info.current_users;
                }
            };

            const Dispatcher = hooks.HookDispatcher(TestHooks);

            TestHooks.called = false;

            Dispatcher.emit(.{ .stair_wait = .{
                .entity = 42,
                .stair_node = 5,
                .direction = .up,
                .waiting_at = 4,
                .current_users = 3,
            } });

            try expect.toBeTrue(TestHooks.called);
            try expect.equal(TestHooks.last_current_users, 3);
        }
    };
};
