const std = @import("std");

test {
    _ = @import("graph_test.zig");
    _ = @import("floyd_warshall_test.zig");
    _ = @import("engine_test.zig");
    _ = @import("controller_cache_test.zig");
    _ = @import("controller_snap_test.zig");
    _ = @import("controller_v4_test.zig");
    _ = @import("reachable_test.zig");
}
