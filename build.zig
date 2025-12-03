const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // zig-utils dependency
    const zig_utils_dep = b.dependency("zig_utils", .{});
    const zig_utils = zig_utils_dep.module("zig_utils");

    // zig-ecs dependency (kept for legacy components)
    const zig_ecs_dep = b.dependency("zig_ecs", .{});
    const zig_ecs = zig_ecs_dep.module("zig-ecs");

    // Main module
    const pathfinding_module = b.addModule("pathfinding", .{
        .root_source_file = b.path("src/pathfinding.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zig_utils", .module = zig_utils },
            .{ .name = "ecs", .module = zig_ecs },
        },
    });

    // zspec dependency
    const zspec = b.dependency("zspec", .{
        .target = target,
        .optimize = optimize,
    });

    // Unit Tests (built-in)
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/pathfinding.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_utils", .module = zig_utils },
                .{ .name = "ecs", .module = zig_ecs },
            },
        }),
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // zspec Tests
    const zspec_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/spec_tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zspec", .module = zspec.module("zspec") },
                .{ .name = "pathfinding", .module = pathfinding_module },
                .{ .name = "zig_utils", .module = zig_utils },
                .{ .name = "ecs", .module = zig_ecs },
            },
        }),
        .test_runner = .{ .path = zspec.path("src/runner.zig"), .mode = .simple },
    });

    const run_zspec_tests = b.addRunArtifact(zspec_tests);
    const zspec_step = b.step("spec", "Run zspec tests");
    zspec_step.dependOn(&run_zspec_tests.step);

    // ===== Usage Examples =====

    // Basic example (recommended starting point)
    const basic_example = b.addExecutable(.{
        .name = "basic_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("usage/basic_example.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pathfinding", .module = pathfinding_module },
            },
        }),
    });
    b.installArtifact(basic_example);

    const run_basic = b.addRunArtifact(basic_example);
    const basic_step = b.step("run-basic", "Run basic example (start here!)");
    basic_step.dependOn(&run_basic.step);

    // Game integration example
    const game_example = b.addExecutable(.{
        .name = "game_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("usage/game_example.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pathfinding", .module = pathfinding_module },
            },
        }),
    });
    b.installArtifact(game_example);

    const run_game = b.addRunArtifact(game_example);
    const game_step = b.step("run-game", "Run game integration example");
    game_step.dependOn(&run_game.step);

    // Platformer example (directional connections)
    const platformer_example = b.addExecutable(.{
        .name = "platformer_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("usage/platformer_example.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pathfinding", .module = pathfinding_module },
            },
        }),
    });
    b.installArtifact(platformer_example);

    const run_platformer = b.addRunArtifact(platformer_example);
    const platformer_step = b.step("run-platformer", "Run platformer example");
    platformer_step.dependOn(&run_platformer.step);

    // Full engine example (all features)
    const engine_example = b.addExecutable(.{
        .name = "engine_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("usage/engine_example.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pathfinding", .module = pathfinding_module },
            },
        }),
    });
    b.installArtifact(engine_example);

    const run_engine = b.addRunArtifact(engine_example);
    const engine_step = b.step("run-engine", "Run full engine example");
    engine_step.dependOn(&run_engine.step);

    // Run all examples
    const examples_step = b.step("run-examples", "Run all usage examples");
    examples_step.dependOn(&run_basic.step);
    examples_step.dependOn(&run_game.step);
    examples_step.dependOn(&run_platformer.step);
    examples_step.dependOn(&run_engine.step);
}
