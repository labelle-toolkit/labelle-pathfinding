const std = @import("std");
const testing = std.testing;
const Batch = @import("pathfinder").PreparationBatch;

fn select(batch: *Batch, budget: usize, pending: []const u64) ![]const u64 {
    try batch.begin(testing.allocator, budget);
    for (pending) |id| batch.consider(id);
    return batch.selected.items;
}

test "rotating batches ignore view order and repeated invalidation cannot jump the queue" {
    var batch = Batch{};
    defer batch.deinit(testing.allocator);
    const pending = [_]u64{ 6, 1, 3, 5, 2, 4 };
    try testing.expectEqualSlices(u64, &.{ 1, 2 }, try select(&batch, 2, &pending));
    batch.finish();
    // 1/2 became stale again; they remain pending but cannot jump ahead.
    try testing.expectEqualSlices(u64, &.{ 3, 4 }, try select(&batch, 2, &pending));
    batch.finish();
    try testing.expectEqualSlices(u64, &.{ 5, 6 }, try select(&batch, 2, &pending));
    batch.finish();
    try testing.expectEqualSlices(u64, &.{ 1, 2 }, try select(&batch, 2, &pending));
}

test "deleted cursor, insertion, duplicate views and wrap retain deterministic order" {
    var batch = Batch{};
    defer batch.deinit(testing.allocator);
    batch.cursor = 3;
    try testing.expectEqualSlices(u64, &.{ 4, 7, 1 }, try select(&batch, 3, &.{ 1, 7, 4, 4, 2, 7 }));
    try testing.expectEqual(@as(usize, 6), batch.inspected);
    batch.finish();
    try testing.expectEqualSlices(u64, &.{ 2, 4, 7 }, try select(&batch, 3, &.{ 7, 4, 2, 1 }));
    batch.reset();
    try testing.expectEqualSlices(u64, &.{1}, try select(&batch, 1, &.{ 7, 4, 2, 1 }));
}

test "zero budget and empty pending view do not advance cursor" {
    var batch = Batch{};
    defer batch.deinit(testing.allocator);
    batch.cursor = 4;
    try testing.expectEqualSlices(u64, &.{}, try select(&batch, 0, &.{ 1, 5 }));
    batch.finish();
    try testing.expectEqual(@as(?u64, 4), batch.cursor);
    try testing.expectEqualSlices(u64, &.{}, try select(&batch, 4, &.{}));
    batch.finish();
    try testing.expectEqual(@as(?u64, 4), batch.cursor);
}

test "allocation failure cannot publish a partial batch or consume a turn" {
    var bytes: [0]u8 = .{};
    var allocator = std.heap.FixedBufferAllocator.init(&bytes);
    var batch = Batch{ .cursor = 4 };
    defer batch.deinit(allocator.allocator());
    try testing.expectError(error.OutOfMemory, batch.begin(allocator.allocator(), 3));
    batch.consider(5);
    try testing.expectEqual(@as(usize, 0), batch.selected.items.len);
    batch.finish();
    try testing.expectEqual(@as(?u64, 4), batch.cursor);
}

test "all permutations agree with the rotated ordering and budget" {
    const values = [_]u64{ 0, 2, 5, 9 };
    var batch = Batch{};
    defer batch.deinit(testing.allocator);
    for (values) |a| for (values) |b| for (values) |c| for (values) |d| {
        if (a == b or a == c or a == d or b == c or b == d or c == d) continue;
        for (0..11) |cursor| {
            for (0..6) |budget| {
                batch.cursor = cursor;
                var expected: [4]u64 = undefined;
                var count: usize = 0;
                for (values) |v| if (v > cursor) {
                    expected[count] = v;
                    count += 1;
                };
                for (values) |v| if (v <= cursor) {
                    expected[count] = v;
                    count += 1;
                };
                try testing.expectEqualSlices(u64, expected[0..@min(budget, 4)], try select(&batch, budget, &.{ a, b, c, d }));
            }
        }
    };
}
