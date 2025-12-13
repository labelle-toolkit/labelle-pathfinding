const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies
    const engine_dep = b.dependency("labelle-engine", .{
        .target = target,
        .optimize = optimize,
    });
    const engine = engine_dep.module("labelle-engine");

    const pathfinding_dep = b.dependency("labelle-pathfinding", .{
        .target = target,
        .optimize = optimize,
    });
    const pathfinding = pathfinding_dep.module("pathfinding");

    // Main executable
    const exe = b.addExecutable(.{
        .name = "integration_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "labelle-engine", .module = engine },
                .{ .name = "pathfinding", .module = pathfinding },
            },
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the integration example");
    run_step.dependOn(&run_cmd.step);
}
