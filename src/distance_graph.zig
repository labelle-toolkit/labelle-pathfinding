//! Distance Graph Interface
//!
//! Defines the contract for pathfinding algorithms that compute distances
//! between vertices. Implementations can use different algorithms like
//! Floyd-Warshall, Dijkstra, A*, etc.

const std = @import("std");

/// Interface for distance graph implementations.
/// Use with comptime duck-typing or contract validation.
pub const DistanceGraph = struct {
    pub fn deinit(self: *DistanceGraph) void {
        _ = self;
    }

    pub fn addEdge(self: *DistanceGraph, u: u32, v: u32, w: u64) void {
        _ = self;
        _ = u;
        _ = v;
        _ = w;
    }

    pub fn hasPath(self: *DistanceGraph, u: usize, v: usize) bool {
        _ = self;
        _ = u;
        _ = v;
        return false;
    }

    pub fn resize(self: *DistanceGraph, size: u32) void {
        _ = self;
        _ = size;
    }

    pub fn addEdgeWithMapping(self: *DistanceGraph, u: u32, v: u32, w: u64) void {
        _ = self;
        _ = u;
        _ = v;
        _ = w;
    }

    pub fn valueWithMapping(self: *DistanceGraph, u: u32, v: u32) u64 {
        _ = self;
        _ = u;
        _ = v;
        return 0;
    }

    pub fn value(self: *DistanceGraph, u: usize, v: usize) u64 {
        _ = self;
        _ = u;
        _ = v;
        return 0;
    }

    pub fn setPathWithMapping(self: *DistanceGraph, path: *std.ArrayList(u32), u: u32, v: u32) !void {
        _ = self;
        _ = path;
        _ = u;
        _ = v;
    }

    pub fn nextWithMapping(self: *DistanceGraph, u: u32, v: u32) u32 {
        _ = self;
        _ = u;
        _ = v;
        return 0;
    }

    pub fn hasPathWithMapping(self: *DistanceGraph, u: u32, v: u32) bool {
        _ = self;
        _ = u;
        _ = v;
        return false;
    }

    pub fn clean(self: *DistanceGraph) !void {
        _ = self;
    }

    pub fn generate(self: *DistanceGraph) void {
        _ = self;
    }
};

/// Validates that a type implements the DistanceGraph interface at comptime.
pub fn validateDistanceGraph(comptime T: type) void {
    const required_fns = .{
        .{ "deinit", fn (*T) void },
        .{ "addEdge", fn (*T, u32, u32, u64) void },
        .{ "hasPath", fn (*T, usize, usize) bool },
        .{ "resize", fn (*T, u32) void },
        .{ "addEdgeWithMapping", fn (*T, u32, u32, u64) void },
        .{ "valueWithMapping", fn (*T, u32, u32) u64 },
        .{ "value", fn (*T, usize, usize) u64 },
        .{ "nextWithMapping", fn (*T, u32, u32) u32 },
        .{ "hasPathWithMapping", fn (*T, u32, u32) bool },
        .{ "generate", fn (*T) void },
    };

    inline for (required_fns) |req| {
        if (!@hasDecl(T, req[0])) {
            @compileError("DistanceGraph implementation missing required function: " ++ req[0]);
        }
    }
}
