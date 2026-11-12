const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Static library for linking
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zig_utils",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(lib);

    // zspec dependency
    const zspec = b.dependency("zspec", .{
        .target = target,
        .optimize = optimize,
    });

    // zig_utils module for tests
    const zig_utils_module = b.addModule("zig_utils", .{
        .root_source_file = b.path("src/root.zig"),
    });

    // Tests with zspec runner
    const lib_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zspec", .module = zspec.module("zspec") },
                .{ .name = "zig_utils", .module = zig_utils_module },
            },
        }),
        .test_runner = .{ .path = zspec.path("src/runner.zig"), .mode = .simple },
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
