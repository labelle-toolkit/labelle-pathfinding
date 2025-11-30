const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // zig-utils dependency
    const zig_utils_dep = b.dependency("zig_utils", .{});
    const zig_utils = zig_utils_dep.module("zig_utils");

    // zig-ecs dependency
    const zig_ecs_dep = b.dependency("zig_ecs", .{});
    const zig_ecs = zig_ecs_dep.module("zig-ecs");

    // Main module
    const pathfinding_module = b.addModule("pathfinding", .{
        .root_source_file = b.path("src/pathfinding.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zig_utils", .module = zig_utils },
            .{ .name = "zig_ecs", .module = zig_ecs },
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
                .{ .name = "zig_ecs", .module = zig_ecs },
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
                .{ .name = "zig_ecs", .module = zig_ecs },
            },
        }),
        .test_runner = .{ .path = zspec.path("src/runner.zig"), .mode = .simple },
    });

    const run_zspec_tests = b.addRunArtifact(zspec_tests);
    const zspec_step = b.step("spec", "Run zspec tests");
    zspec_step.dependOn(&run_zspec_tests.step);

    // ===== Usage Examples =====

    // Floyd-Warshall example
    const floyd_example = b.addExecutable(.{
        .name = "floyd_warshall_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("usage/floyd_warshall_example.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pathfinding", .module = pathfinding_module },
            },
        }),
    });
    b.installArtifact(floyd_example);

    const run_floyd = b.addRunArtifact(floyd_example);
    const floyd_step = b.step("run-floyd", "Run Floyd-Warshall example");
    floyd_step.dependOn(&run_floyd.step);

    // A* example
    const astar_example = b.addExecutable(.{
        .name = "a_star_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("usage/a_star_example.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pathfinding", .module = pathfinding_module },
            },
        }),
    });
    b.installArtifact(astar_example);

    const run_astar = b.addRunArtifact(astar_example);
    const astar_step = b.step("run-astar", "Run A* algorithm example");
    astar_step.dependOn(&run_astar.step);

    // Comparison example
    const compare_example = b.addExecutable(.{
        .name = "comparison_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("usage/comparison_example.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pathfinding", .module = pathfinding_module },
            },
        }),
    });
    b.installArtifact(compare_example);

    const run_compare = b.addRunArtifact(compare_example);
    const compare_step = b.step("run-compare", "Run algorithm comparison example");
    compare_step.dependOn(&run_compare.step);

    // Run all examples
    const examples_step = b.step("run-examples", "Run all usage examples");
    examples_step.dependOn(&run_floyd.step);
    examples_step.dependOn(&run_astar.step);
    examples_step.dependOn(&run_compare.step);
}
