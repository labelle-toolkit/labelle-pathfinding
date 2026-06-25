const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies.
    const zig_utils = b.dependency("zig_utils", .{}).module("zig_utils");
    const core_mod = b.dependency("labelle_core", .{
        .target = target,
        .optimize = optimize,
    }).module("labelle-core");
    const zspec = b.dependency("zspec", .{ .target = target, .optimize = optimize });

    // Main module — navigation layer (Controller + pure engine) at the top level,
    // standalone algorithm core under `.algo`.
    const pathfinding_module = b.addModule("labelle_pathfinding", .{
        .root_source_file = b.path("src/pathfinding.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zig_utils", .module = zig_utils },
            .{ .name = "labelle-core", .module = core_mod },
        },
    });

    // Unit tests (refAllDecls over the nav layer + algorithm core).
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/pathfinding.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_utils", .module = zig_utils },
                .{ .name = "labelle-core", .module = core_mod },
            },
        }),
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Navigation tests (ported from the in-tree FP pathfinder). They import the
    // package as `pathfinder` — the same module under that name.
    const nav_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/nav/root.zig"),
            .target = target,
            .optimize = optimize,
            // The zspec runner's JUnit writer uses libc (std.c). macOS links it by
            // default; on Linux CI it must be explicit, or the test fails to compile.
            .link_libc = true,
            .imports = &.{
                .{ .name = "pathfinder", .module = pathfinding_module },
                .{ .name = "labelle-core", .module = core_mod },
                .{ .name = "zig_utils", .module = zig_utils },
            },
        }),
        .test_runner = .{ .path = zspec.path("src/runner.zig"), .mode = .simple },
    });
    const run_nav_tests = b.addRunArtifact(nav_tests);

    // `test` = built-in unit tests; `spec` = the zspec-based navigation tests.
    // (CI runs both steps; keep them split so each maps to a CI job.)
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const spec_step = b.step("spec", "Run zspec navigation tests");
    spec_step.dependOn(&run_nav_tests.step);
}
