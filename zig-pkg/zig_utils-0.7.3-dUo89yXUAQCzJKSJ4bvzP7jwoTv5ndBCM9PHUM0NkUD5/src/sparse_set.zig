//! Sparse Set
//!
//! O(1) lookup, insert, remove with cache-friendly iteration.
//! Used for entity -> physics body mappings.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Generic sparse set for mapping keys to values
/// KeyType must be an unsigned integer type (u8, u16, u32, u64, usize)
pub fn SparseSet(comptime KeyType: type, comptime T: type) type {
    comptime {
        const info = @typeInfo(KeyType);
        if (info != .int or info.int.signedness != .unsigned) {
            @compileError("KeyType must be an unsigned integer type");
        }
    }

    return struct {
        const Self = @This();

        allocator: Allocator,
        sparse: []?u32,        // key -> dense_index
        dense_keys: []KeyType, // dense_index -> key
        dense_values: []T,     // dense_index -> value
        count: usize,
        capacity: usize,
        max_key: usize,

        pub fn init(allocator: Allocator, max_keys: usize, initial_capacity: usize) !Self {
            const sparse = try allocator.alloc(?u32, max_keys);
            errdefer allocator.free(sparse);
            @memset(sparse, null);

            const dense_keys = try allocator.alloc(KeyType, initial_capacity);
            errdefer allocator.free(dense_keys);

            const dense_values = try allocator.alloc(T, initial_capacity);
            errdefer allocator.free(dense_values);

            return Self{
                .allocator = allocator,
                .sparse = sparse,
                .dense_keys = dense_keys,
                .dense_values = dense_values,
                .count = 0,
                .capacity = initial_capacity,
                .max_key = max_keys,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.sparse);
            self.allocator.free(self.dense_keys);
            self.allocator.free(self.dense_values);
        }

        /// Insert or update a key-value pair
        pub fn put(self: *Self, key: KeyType, value: T) !void {
            if (key >= self.max_key) return error.KeyOutOfRange;

            // Update existing
            if (self.sparse[key]) |idx| {
                self.dense_values[idx] = value;
                return;
            }

            // Grow if needed
            if (self.count >= self.capacity) {
                const new_cap = if (self.capacity == 0) 4 else self.capacity * 2;
                try self.grow(new_cap);
            }

            if (self.count >= std.math.maxInt(u32)) return error.CapacityExceeded;
            const idx: u32 = @intCast(self.count);
            self.sparse[key] = idx;
            self.dense_keys[idx] = key;
            self.dense_values[idx] = value;
            self.count += 1;
        }

        /// Atomically grow both dense arrays
        fn grow(self: *Self, new_cap: usize) !void {
            // Allocate new arrays first (no state change yet)
            const new_keys = try self.allocator.alloc(KeyType, new_cap);
            errdefer self.allocator.free(new_keys);

            const new_values = try self.allocator.alloc(T, new_cap);

            // Copy existing data
            @memcpy(new_keys[0..self.count], self.dense_keys[0..self.count]);
            @memcpy(new_values[0..self.count], self.dense_values[0..self.count]);

            // Free old arrays
            self.allocator.free(self.dense_keys);
            self.allocator.free(self.dense_values);

            // Update state atomically
            self.dense_keys = new_keys;
            self.dense_values = new_values;
            self.capacity = new_cap;
        }

        /// Get value for key
        pub fn get(self: *const Self, key: KeyType) ?T {
            if (key >= self.max_key) return null;
            const idx = self.sparse[key] orelse return null;
            return self.dense_values[idx];
        }

        /// Get pointer to value for key
        pub fn getPtr(self: *Self, key: KeyType) ?*T {
            if (key >= self.max_key) return null;
            const idx = self.sparse[key] orelse return null;
            return &self.dense_values[idx];
        }

        /// Check if key exists
        pub fn contains(self: *const Self, key: KeyType) bool {
            if (key >= self.max_key) return false;
            return self.sparse[key] != null;
        }

        /// Remove key-value pair
        pub fn remove(self: *Self, key: KeyType) void {
            if (key >= self.max_key) return;
            const idx = self.sparse[key] orelse return;

            // Swap with last element
            const last_idx = self.count - 1;
            if (idx != last_idx) {
                const last_key = self.dense_keys[last_idx];
                self.dense_keys[idx] = last_key;
                self.dense_values[idx] = self.dense_values[last_idx];
                self.sparse[last_key] = idx;
            }

            self.sparse[key] = null;
            self.count -= 1;
        }

        /// Clear all entries
        pub fn clear(self: *Self) void {
            for (self.dense_keys[0..self.count]) |key| {
                self.sparse[key] = null;
            }
            self.count = 0;
        }

        /// Iterate over all values (cache-friendly)
        pub fn values(self: *const Self) []const T {
            return self.dense_values[0..self.count];
        }

        /// Iterate over all keys
        pub fn keys(self: *const Self) []const KeyType {
            return self.dense_keys[0..self.count];
        }

        /// Get key-value pairs for iteration
        pub const Entry = struct {
            key: KeyType,
            value: *T,
        };

        pub fn iterator(self: *Self) Iterator {
            return .{ .set = self, .index = 0 };
        }

        pub const Iterator = struct {
            set: *Self,
            index: usize,

            pub fn next(self: *Iterator) ?Entry {
                if (self.index >= self.set.count) return null;
                const entry = Entry{
                    .key = self.set.dense_keys[self.index],
                    .value = &self.set.dense_values[self.index],
                };
                self.index += 1;
                return entry;
            }
        };

        /// Number of entries
        pub fn len(self: *const Self) usize {
            return self.count;
        }
    };
}
