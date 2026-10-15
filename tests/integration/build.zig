const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const engine = b.dependency("engine", .{ .target = target, .optimize = optimize }).module("engine");
    const pathfinder = b.dependency("pathfinder", .{ .target = target, .optimize = optimize }).module("labelle_pathfinding");
    const core = engine.import_table.get("labelle-core").?;
    pathfinder.addImport("labelle-core", core);
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("preparation_test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{ .{ .name = "engine", .module = engine }, .{ .name = "pathfinder", .module = pathfinder }, .{ .name = "labelle-core", .module = core } },
    }) });
    b.step("test", "Run preparation with the real engine's headless ECS game").dependOn(&b.addRunArtifact(tests).step);
}
