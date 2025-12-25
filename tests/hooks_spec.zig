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
};
