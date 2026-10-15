//! Compile the real controller lifecycle for wasm32. No browser or SDK needed.
//! Exporting the identity forces code generation for State.init, unlike decl-only
//! checks which missed the unsupported u64 atomic in the preparation counter.
const std = @import("std");
const pathfinder = @import("pathfinder");

export fn preparationWorldIdentity() u64 {
    var memory: [32768]u8 = undefined;
    var allocator = std.heap.FixedBufferAllocator.init(&memory);
    var state = pathfinder.controller.State.init(allocator.allocator());
    defer state.deinit();
    return state.preparation_world;
}
