//! Z-Index Bucket Storage
//!
//! Maintains items sorted by z-index using configurable buckets.
//! This eliminates the need to re-sort the entire list when z-indices change.
//!
//! Complexity:
//! - Insert: O(1) amortized
//! - Remove: O(bucket_size) - typically small due to clustered z-indices
//! - Change z-index: O(bucket_size)
//! - Iteration: O(bucket_count + n) ≈ O(n)

const std = @import("std");

/// Z-index bucket storage for efficient ordered iteration.
/// Generic over:
/// - T: item type
/// - ZIndexType: unsigned integer type for z-index (u8, u16, etc.)
///
/// The number of buckets is determined by the max value of ZIndexType + 1.
/// For u8: 256 buckets, for u4: 16 buckets, etc.
pub fn ZIndexBuckets(comptime T: type, comptime ZIndexType: type) type {
    comptime {
        const info = @typeInfo(ZIndexType);
        if (info != .int or info.int.signedness != .unsigned) {
            @compileError("ZIndexType must be an unsigned integer type");
        }
    }

    const bucket_count = std.math.maxInt(ZIndexType) + 1;

    return struct {
        const Self = @This();
        const Bucket = std.ArrayListUnmanaged(T);

        buckets: [bucket_count]Bucket,
        allocator: std.mem.Allocator,
        total_count: usize,

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .buckets = [_]Bucket{.{}} ** bucket_count,
                .allocator = allocator,
                .total_count = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            for (&self.buckets) |*bucket| {
                bucket.deinit(self.allocator);
            }
        }

        /// Insert an item at the given z-index
        pub fn insert(self: *Self, item: T, z: ZIndexType) !void {
            try self.buckets[z].append(self.allocator, item);
            self.total_count += 1;
        }

        /// Remove an item from the given z-index bucket using equality comparison.
        /// Returns true if the item was found and removed.
        pub fn remove(self: *Self, item: T, z: ZIndexType) bool {
            const bucket = &self.buckets[z];
            for (bucket.items, 0..) |existing, i| {
                if (eql(existing, item)) {
                    _ = bucket.swapRemove(i);
                    self.total_count -= 1;
                    return true;
                }
            }
            return false;
        }

        /// Change an item's z-index from old_z to new_z
        /// Returns error if the item was not found at old_z or allocation fails
        pub fn changeZIndex(self: *Self, item: T, old_z: ZIndexType, new_z: ZIndexType) !void {
            if (old_z == new_z) return;

            // First verify item exists at old_z before making any changes
            const bucket = &self.buckets[old_z];
            var found_index: ?usize = null;
            for (bucket.items, 0..) |existing, i| {
                if (eql(existing, item)) {
                    found_index = i;
                    break;
                }
            }
            if (found_index == null) {
                return error.ItemNotFound;
            }

            // Insert to new bucket first - if this fails, no state has changed
            try self.buckets[new_z].append(self.allocator, item);

            // Now safe to remove from old bucket (insert succeeded)
            _ = bucket.swapRemove(found_index.?);
            // total_count stays the same (removed one, added one)
        }

        /// Get total number of items across all buckets
        pub fn count(self: *const Self) usize {
            return self.total_count;
        }

        /// Clear all buckets
        pub fn clear(self: *Self) void {
            for (&self.buckets) |*bucket| {
                bucket.clearRetainingCapacity();
            }
            self.total_count = 0;
        }

        /// Iterator that yields items in z-index order (0 to max)
        pub fn iterator(self: *const Self) Iterator {
            return Iterator.init(self);
        }

        pub const Iterator = struct {
            buckets: *const [bucket_count]Bucket,
            z: usize,
            idx: usize,

            pub fn init(storage: *const Self) Iterator {
                var iter = Iterator{
                    .buckets = &storage.buckets,
                    .z = 0,
                    .idx = 0,
                };
                iter.skipEmptyBuckets();
                return iter;
            }

            pub fn next(self: *Iterator) ?T {
                while (self.z < bucket_count) {
                    const bucket = &self.buckets[self.z];
                    if (self.idx < bucket.items.len) {
                        const item = bucket.items[self.idx];
                        self.idx += 1;
                        return item;
                    }
                    self.z += 1;
                    self.idx = 0;
                }
                return null;
            }

            fn skipEmptyBuckets(self: *Iterator) void {
                while (self.z < bucket_count and self.buckets[self.z].items.len == 0) {
                    self.z += 1;
                }
            }

            pub fn reset(self: *Iterator) void {
                self.z = 0;
                self.idx = 0;
                self.skipEmptyBuckets();
            }
        };

        /// Collect all items into a slice in z-index order.
        /// The caller must provide a buffer of at least `count()` size.
        pub fn collectInto(self: *const Self, buffer: []T) []T {
            var i: usize = 0;
            var iter = self.iterator();
            while (iter.next()) |item| {
                if (i >= buffer.len) break;
                buffer[i] = item;
                i += 1;
            }
            return buffer[0..i];
        }

        /// Equality comparison for items
        fn eql(a: T, b: T) bool {
            // Use eql method if available (for structs), otherwise use std.meta.eql
            const info = @typeInfo(T);
            if (info == .@"struct" and @hasDecl(T, "eql")) {
                return a.eql(b);
            } else {
                return std.meta.eql(a, b);
            }
        }
    };
}
