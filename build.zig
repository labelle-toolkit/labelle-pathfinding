const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // labelle dependency
    const labelle = b.dependency("labelle", .{
        .target = target,
        .optimize = optimize,
    });

    // Main module
    const pathfinding_module = b.addModule("pathfinding", .{
        .root_source_file = b.path("src/pathfinding.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "labelle", .module = labelle.module("labelle") },
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
                .{ .name = "labelle", .module = labelle.module("labelle") },
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
                .{ .name = "labelle", .module = labelle.module("labelle") },
            },
        }),
        .test_runner = .{ .path = zspec.path("src/runner.zig"), .mode = .simple },
    });

    const run_zspec_tests = b.addRunArtifact(zspec_tests);
    const zspec_step = b.step("spec", "Run zspec tests");
    zspec_step.dependOn(&run_zspec_tests.step);
}
