const std = @import("std");

pub fn build(b: *std.Build) void {
    const opts = .{ .target = b.standardTargetOptions(.{}), .optimize = b.standardOptimizeOption(.{}) };
    const test_artifact = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("grid_test.zig"),
        .target = opts.target,
        .optimize = opts.optimize,
        .imports = &.{
            .{ .name = "engine", .module = b.dependency("engine", opts).module("engine") },
            .{ .name = "pathfinder", .module = b.dependency("pathfinding", opts).module("labelle_pathfinding") },
        },
    }) });
    b.step("test", "Test the grid with a real Labelle engine Game").dependOn(&b.addRunArtifact(test_artifact).step);
}
