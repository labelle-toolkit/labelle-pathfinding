//! Optimized Floyd-Warshall Algorithm Implementation
//!
//! High-performance implementation with:
//! - Flat memory layout for cache efficiency
//! - SIMD vectorization for inner loop operations
//! - Multi-threaded parallelization across rows
//!
//! For graphs that change infrequently but require many arbitrary
//! source-destination queries.

const std = @import("std");

const INF: u32 = std.math.maxInt(u32);

/// Configuration for the optimized Floyd-Warshall algorithm
pub const Config = struct {
    /// Enable multi-threaded parallelization (recommended for graphs with 256+ nodes)
    parallel: bool = true,
    /// Enable SIMD vectorization
    simd: bool = true,
};

/// Optimized Floyd-Warshall all-pairs shortest path algorithm.
/// Uses flat memory layout, SIMD, and multi-threading for performance.
pub fn FloydWarshallOptimized(comptime config: Config) type {
    return struct {
        const Self = @This();

        // SIMD vector width (4 x u32 = 128 bits, widely supported)
        const VectorWidth = 4;
        const DistVector = @Vector(VectorWidth, u32);
        const IndexVector = @Vector(VectorWidth, u32);

        size: u32 = 0,
        capacity: u32 = 0,
        /// Flat distance matrix (size x size), row-major order
        dist: []u32,
        /// Flat next-hop matrix (size x size), row-major order
        next: []u32,
        /// Entity ID to internal index mapping
        ids: std.AutoHashMap(u32, u32),
        /// Reverse mapping: internal index to entity ID.
        /// Provides O(1) reverse lookups, significantly faster than the legacy
        /// implementation which required O(n) iteration for each reverse lookup.
        reverse_ids: std.AutoHashMap(u32, u32),
        last_key: u32 = 0,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .dist = &.{},
                .next = &.{},
                .ids = std.AutoHashMap(u32, u32).init(allocator),
                .reverse_ids = std.AutoHashMap(u32, u32).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.dist.len > 0) {
                self.allocator.free(self.dist);
            }
            if (self.next.len > 0) {
                self.allocator.free(self.next);
            }
            self.ids.deinit();
            self.reverse_ids.deinit();
        }

        /// Generate a new internal key for entity mapping
        pub fn newKey(self: *Self) u32 {
            self.last_key += 1;
            return self.last_key - 1;
        }

        /// Get flat array index for (row, col)
        inline fn index(self: *const Self, row: u32, col: u32) usize {
            return @as(usize, row) * @as(usize, self.size) + @as(usize, col);
        }

        /// Add an edge between two vertices with given weight (direct index)
        pub fn addEdge(self: *Self, u: u32, v: u32, w: u32) void {
            self.dist[self.index(u, v)] = w;
        }

        /// Get the distance between two vertices (direct index)
        pub fn value(self: *const Self, u: u32, v: u32) u32 {
            return self.dist[self.index(u, v)];
        }

        /// Check if a path exists between two vertices (direct index)
        pub fn hasPath(self: *const Self, u: u32, v: u32) bool {
            return self.dist[self.index(u, v)] != INF;
        }

        /// Get the next vertex in the shortest path from u to v (direct index)
        pub fn getNext(self: *const Self, u: u32, v: u32) u32 {
            return self.next[self.index(u, v)];
        }

        /// Resize the graph to support a given number of vertices
        pub fn resize(self: *Self, new_size: u32) void {
            self.size = new_size;
        }

        /// Add an edge using entity ID mapping (auto-assigns internal indices)
        /// Returns error.OutOfMemory if the internal hash maps fail to allocate
        pub fn addEdgeWithMapping(self: *Self, u: u32, v: u32, w: u32) !void {
            if (!self.ids.contains(u)) {
                const key = self.newKey();
                try self.ids.put(u, key);
                try self.reverse_ids.put(key, u);
            }
            if (!self.ids.contains(v)) {
                const key = self.newKey();
                try self.ids.put(v, key);
                try self.reverse_ids.put(key, v);
            }
            self.addEdge(self.ids.get(u).?, self.ids.get(v).?, w);
        }

        /// Get the distance between two entities (using ID mapping)
        pub fn valueWithMapping(self: *const Self, u: u32, v: u32) u32 {
            const u_idx = self.ids.get(u) orelse return INF;
            const v_idx = self.ids.get(v) orelse return INF;
            return self.value(u_idx, v_idx);
        }

        /// Get the next entity in the shortest path from u to v (using ID mapping)
        /// Returns INF if no path exists
        pub fn nextWithMapping(self: *const Self, u: u32, v: u32) u32 {
            const u_idx = self.ids.get(u) orelse return INF;
            const v_idx = self.ids.get(v) orelse return INF;
            const next_idx = self.getNext(u_idx, v_idx);
            return self.reverse_ids.get(next_idx) orelse INF;
        }

        /// Check if a path exists between two entities (using ID mapping)
        pub fn hasPathWithMapping(self: *const Self, u: u32, v: u32) bool {
            const u_idx = self.ids.get(u) orelse return false;
            const v_idx = self.ids.get(v) orelse return false;
            return self.hasPath(u_idx, v_idx);
        }

        pub const PathError = error{
            NoPathFound,
            OutOfMemory,
        };

        /// Build the path from u to v and store in the provided ArrayList
        /// Returns error.NoPathFound if no path exists between the nodes
        pub fn setPathWithMapping(self: *const Self, path_list: *std.array_list.Managed(u32), u_node: u32, v_node: u32) PathError!void {
            var current = u_node;
            while (current != v_node) {
                try path_list.append(current);
                current = self.nextWithMapping(current, v_node);
                if (current == INF) {
                    return error.NoPathFound;
                }
            }
            try path_list.append(v_node);
        }

        /// Build the path from u to v and store in the provided unmanaged ArrayList
        /// Returns error.NoPathFound if no path exists between the nodes
        pub fn setPathWithMappingUnmanaged(self: *const Self, allocator: std.mem.Allocator, path_list: *std.ArrayListUnmanaged(u32), u_node: u32, v_node: u32) PathError!void {
            var current = u_node;
            while (current != v_node) {
                try path_list.append(allocator, current);
                current = self.nextWithMapping(current, v_node);
                if (current == INF) {
                    return error.NoPathFound;
                }
            }
            try path_list.append(allocator, v_node);
        }

        pub const CleanError = error{
            SizeOverflow,
            OutOfMemory,
        };

        /// Reset the graph and prepare for new data
        pub fn clean(self: *Self) CleanError!void {
            self.last_key = 0;
            self.ids.clearRetainingCapacity();
            self.reverse_ids.clearRetainingCapacity();

            // Check for overflow before computing matrix_size
            const n: usize = self.size;
            const matrix_size = std.math.mul(usize, n, n) catch return error.SizeOverflow;

            // Reallocate if needed
            if (self.capacity < self.size) {
                if (self.dist.len > 0) {
                    self.allocator.free(self.dist);
                }
                if (self.next.len > 0) {
                    self.allocator.free(self.next);
                }
                self.dist = try self.allocator.alloc(u32, matrix_size);
                self.next = try self.allocator.alloc(u32, matrix_size);
                self.capacity = self.size;
            }

            // Initialize matrices
            const dist_slice = self.dist[0..matrix_size];
            const next_slice = self.next[0..matrix_size];

            // Set all distances to INF
            @memset(dist_slice, INF);

            // Initialize next-hop and diagonal
            for (0..self.size) |i| {
                for (0..self.size) |j| {
                    const idx = i * self.size + j;
                    next_slice[idx] = @intCast(j);
                }
                // Self-loops have distance 0
                dist_slice[i * self.size + i] = 0;
            }
        }

        /// Run the Floyd-Warshall algorithm to compute all shortest paths
        pub fn generate(self: *Self) void {
            if (config.parallel and self.size > 64) {
                self.generateParallel();
            } else if (config.simd) {
                self.generateSimd();
            } else {
                self.generateScalar();
            }
        }

        /// Scalar implementation (baseline)
        fn generateScalar(self: *Self) void {
            const n = self.size;
            for (0..n) |k| {
                for (0..n) |i| {
                    const dist_ik = self.dist[i * n + k];
                    if (dist_ik == INF) continue; // Optimization: skip if no path to k

                    for (0..n) |j| {
                        const dist_kj = self.dist[k * n + j];
                        if (dist_kj == INF) continue;

                        const new_dist = dist_ik +| dist_kj; // Saturating add to prevent overflow
                        const idx = i * n + j;
                        if (new_dist < self.dist[idx]) {
                            self.dist[idx] = new_dist;
                            self.next[idx] = self.next[i * n + k];
                        }
                    }
                }
            }
        }

        /// SIMD-optimized implementation
        fn generateSimd(self: *Self) void {
            const n = self.size;
            const n_usize: usize = n;

            for (0..n) |k| {
                for (0..n) |i| {
                    const dist_ik = self.dist[i * n_usize + k];
                    if (dist_ik == INF) continue;

                    const next_ik = self.next[i * n_usize + k];
                    const dist_ik_vec: DistVector = @splat(dist_ik);
                    const next_ik_vec: IndexVector = @splat(next_ik);

                    const row_i_start = i * n_usize;
                    const row_k_start = k * n_usize;

                    // Process in SIMD chunks
                    var j: usize = 0;
                    while (j + VectorWidth <= n_usize) : (j += VectorWidth) {
                        // Load dist[k][j..j+VectorWidth]
                        const dist_kj_vec: DistVector = self.dist[row_k_start + j ..][0..VectorWidth].*;

                        // Load current dist[i][j..j+VectorWidth]
                        const dist_ij_ptr = self.dist[row_i_start + j ..][0..VectorWidth];
                        const dist_ij_vec: DistVector = dist_ij_ptr.*;

                        // Load current next[i][j..j+VectorWidth]
                        const next_ij_ptr = self.next[row_i_start + j ..][0..VectorWidth];
                        const next_ij_vec: IndexVector = next_ij_ptr.*;

                        // Calculate new distances (saturating add)
                        const new_dist_vec = dist_ik_vec +| dist_kj_vec;

                        // Compare: new_dist < dist_ij
                        const mask = new_dist_vec < dist_ij_vec;

                        // Select: if mask then new_dist else dist_ij
                        dist_ij_ptr.* = @select(u32, mask, new_dist_vec, dist_ij_vec);
                        next_ij_ptr.* = @select(u32, mask, next_ik_vec, next_ij_vec);
                    }

                    // Handle remaining elements
                    while (j < n_usize) : (j += 1) {
                        const dist_kj = self.dist[row_k_start + j];
                        if (dist_kj == INF) continue;

                        const new_dist = dist_ik +| dist_kj;
                        const idx = row_i_start + j;
                        if (new_dist < self.dist[idx]) {
                            self.dist[idx] = new_dist;
                            self.next[idx] = next_ik;
                        }
                    }
                }
            }
        }

        /// Multi-threaded parallel implementation using row decomposition
        /// Based on the semaphore-per-row synchronization pattern
        fn generateParallel(self: *Self) void {
            const n = self.size;
            if (n == 0) return;

            // Determine thread count
            const cpu_count = std.Thread.getCpuCount() catch 4;
            const thread_count: usize = @min(cpu_count, n);

            // Fall back to SIMD for small graphs or single core
            if (thread_count <= 1 or n < 32) {
                self.generateSimd();
                return;
            }

            // Allocate synchronization counters (one per k value + 1)
            // Each counter tracks how many threads have signaled that row k is ready
            const sync_counters = self.allocator.alloc(std.atomic.Value(u32), n + 1) catch {
                self.generateSimd();
                return;
            };
            defer self.allocator.free(sync_counters);

            // Initialize: first counter allows all threads to start, rest are 0
            sync_counters[0] = std.atomic.Value(u32).init(@intCast(thread_count));
            for (1..n + 1) |i| {
                sync_counters[i] = std.atomic.Value(u32).init(0);
            }

            // Calculate row distribution
            const rows_per_thread = n / thread_count;
            const extra_rows = n % thread_count;

            // Spawn worker threads
            const threads = self.allocator.alloc(std.Thread, thread_count - 1) catch {
                self.generateSimd();
                return;
            };
            defer self.allocator.free(threads);

            var next_row: usize = 0;
            for (0..thread_count - 1) |t| {
                const start = next_row;
                var end = start + rows_per_thread;
                if (t < extra_rows) end += 1;
                next_row = end;

                threads[t] = std.Thread.spawn(.{}, parallelWorker, .{
                    self,
                    start,
                    end,
                    thread_count,
                    sync_counters,
                }) catch {
                    // If thread spawn fails, fall back to SIMD
                    self.generateSimd();
                    return;
                };
            }

            // Main thread processes its portion
            const main_start = next_row;
            const main_end = n;
            self.parallelWorkerImpl(main_start, main_end, thread_count, sync_counters);

            // Join all threads
            for (threads) |t| {
                t.join();
            }
        }

        /// Worker function for parallel threads
        fn parallelWorker(
            self: *Self,
            start_row: usize,
            end_row: usize,
            thread_count: usize,
            sync_counters: []std.atomic.Value(u32),
        ) void {
            self.parallelWorkerImpl(start_row, end_row, thread_count, sync_counters);
        }

        /// Implementation of parallel worker logic
        fn parallelWorkerImpl(
            self: *Self,
            start_row: usize,
            end_row: usize,
            thread_count: usize,
            sync_counters: []std.atomic.Value(u32),
        ) void {
            const n = self.size;
            const thread_count_u32: u32 = @intCast(thread_count);

            for (0..n) |k| {
                // Wait until row k is ready (counter reaches thread_count)
                // Use a spin loop with exponential backoff
                var spins: u32 = 0;
                while (sync_counters[k].load(.acquire) < thread_count_u32) {
                    spins += 1;
                    if (spins < 100) {
                        std.atomic.spinLoopHint();
                    } else {
                        // Yield to OS scheduler after spinning
                        std.Thread.yield() catch {};
                        spins = 0;
                    }
                }

                // Process our assigned rows for this k iteration (with SIMD)
                for (start_row..end_row) |i| {
                    self.processRowSimd(k, i);
                }

                // If we own row k, signal that row k+1 is ready
                // Each thread that owns row k signals all threads
                if (k >= start_row and k < end_row) {
                    _ = sync_counters[k + 1].fetchAdd(thread_count_u32, .release);
                }
            }
        }

        /// Process a single row with SIMD (for parallel use)
        fn processRowSimd(self: *Self, k: usize, i: usize) void {
            const n = self.size;
            const n_usize: usize = n;

            const dist_ik = self.dist[i * n_usize + k];
            if (dist_ik == INF) return;

            const next_ik = self.next[i * n_usize + k];
            const dist_ik_vec: DistVector = @splat(dist_ik);
            const next_ik_vec: IndexVector = @splat(next_ik);

            const row_i_start = i * n_usize;
            const row_k_start = k * n_usize;

            // SIMD processing
            var j: usize = 0;
            while (j + VectorWidth <= n_usize) : (j += VectorWidth) {
                const dist_kj_vec: DistVector = self.dist[row_k_start + j ..][0..VectorWidth].*;
                const dist_ij_ptr = self.dist[row_i_start + j ..][0..VectorWidth];
                const dist_ij_vec: DistVector = dist_ij_ptr.*;
                const next_ij_ptr = self.next[row_i_start + j ..][0..VectorWidth];
                const next_ij_vec: IndexVector = next_ij_ptr.*;

                const new_dist_vec = dist_ik_vec +| dist_kj_vec;
                const mask = new_dist_vec < dist_ij_vec;

                dist_ij_ptr.* = @select(u32, mask, new_dist_vec, dist_ij_vec);
                next_ij_ptr.* = @select(u32, mask, next_ik_vec, next_ij_vec);
            }

            // Handle remaining elements
            while (j < n_usize) : (j += 1) {
                const dist_kj = self.dist[row_k_start + j];
                if (dist_kj == INF) continue;

                const new_dist = dist_ik +| dist_kj;
                const idx = row_i_start + j;
                if (new_dist < self.dist[idx]) {
                    self.dist[idx] = new_dist;
                    self.next[idx] = next_ik;
                }
            }
        }
    };
}

/// Parallel + SIMD optimized Floyd-Warshall (best for large graphs 256+ nodes)
/// Uses multi-threading with row decomposition and SIMD vectorization within each thread.
pub const FloydWarshallParallel = FloydWarshallOptimized(.{
    .parallel = true,
    .simd = true,
});

/// SIMD-only version (no threading overhead for smaller graphs)
pub const FloydWarshallSimd = FloydWarshallOptimized(.{
    .parallel = false,
    .simd = true,
});

/// Scalar version (for comparison/debugging)
pub const FloydWarshallScalar = FloydWarshallOptimized(.{
    .parallel = false,
    .simd = false,
});

// Unit tests
test "FloydWarshallOptimized basic functionality" {
    const allocator = std.testing.allocator;

    var fw = FloydWarshallSimd.init(allocator);
    defer fw.deinit();

    fw.resize(4);
    try fw.clean();

    // Create graph: 0 -> 1 -> 2 -> 3
    fw.addEdge(0, 1, 1);
    fw.addEdge(1, 2, 1);
    fw.addEdge(2, 3, 1);

    fw.generate();

    // Check distances
    try std.testing.expectEqual(@as(u32, 0), fw.value(0, 0));
    try std.testing.expectEqual(@as(u32, 1), fw.value(0, 1));
    try std.testing.expectEqual(@as(u32, 2), fw.value(0, 2));
    try std.testing.expectEqual(@as(u32, 3), fw.value(0, 3));

    // Check next hops
    try std.testing.expectEqual(@as(u32, 1), fw.getNext(0, 3));
    try std.testing.expectEqual(@as(u32, 2), fw.getNext(1, 3));
}

test "FloydWarshallOptimized with entity mapping" {
    const allocator = std.testing.allocator;

    var fw = FloydWarshallSimd.init(allocator);
    defer fw.deinit();

    fw.resize(4);
    try fw.clean();

    // Use entity IDs: 100 -> 200 -> 300 -> 400
    try fw.addEdgeWithMapping(100, 200, 1);
    try fw.addEdgeWithMapping(200, 300, 1);
    try fw.addEdgeWithMapping(300, 400, 1);

    fw.generate();

    // Check paths exist
    try std.testing.expect(fw.hasPathWithMapping(100, 400));
    try std.testing.expect(fw.hasPathWithMapping(100, 200));

    // Check distances
    try std.testing.expectEqual(@as(u32, 1), fw.valueWithMapping(100, 200));
    try std.testing.expectEqual(@as(u32, 3), fw.valueWithMapping(100, 400));

    // Check next hops
    try std.testing.expectEqual(@as(u32, 200), fw.nextWithMapping(100, 400));
}

test "FloydWarshallOptimized weighted shortest path" {
    const allocator = std.testing.allocator;

    var fw = FloydWarshallSimd.init(allocator);
    defer fw.deinit();

    fw.resize(4);
    try fw.clean();

    // Graph with two paths to node 3:
    // 0 --5--> 1 --3--> 3  (total: 8)
    // 0 --2--> 2 --2--> 3  (total: 4) <- shorter
    fw.addEdge(0, 1, 5);
    fw.addEdge(1, 3, 3);
    fw.addEdge(0, 2, 2);
    fw.addEdge(2, 3, 2);

    fw.generate();

    // Should find shortest path
    try std.testing.expectEqual(@as(u32, 4), fw.value(0, 3));
    try std.testing.expectEqual(@as(u32, 2), fw.getNext(0, 3)); // Goes through node 2
}

test "FloydWarshallOptimized path reconstruction" {
    const allocator = std.testing.allocator;

    var fw = FloydWarshallSimd.init(allocator);
    defer fw.deinit();

    fw.resize(4);
    try fw.clean();

    try fw.addEdgeWithMapping(10, 20, 1);
    try fw.addEdgeWithMapping(20, 30, 1);
    try fw.addEdgeWithMapping(30, 40, 1);

    fw.generate();

    var path = std.ArrayListUnmanaged(u32){};
    defer path.deinit(allocator);

    try fw.setPathWithMappingUnmanaged(allocator, &path, 10, 40);

    try std.testing.expectEqual(@as(usize, 4), path.items.len);
    try std.testing.expectEqual(@as(u32, 10), path.items[0]);
    try std.testing.expectEqual(@as(u32, 20), path.items[1]);
    try std.testing.expectEqual(@as(u32, 30), path.items[2]);
    try std.testing.expectEqual(@as(u32, 40), path.items[3]);
}
