const std = @import("std");

/// Bounded execution scratch, not an authoritative pending queue. Feed the
/// current ECS-derived pending entity identities on every pass. The owner is
/// world-local and must reset the cursor on a world change. Full entity IDs
/// must include generation (or use a stable, generation-qualified ordering).
pub const PreparationBatch = struct {
    selected: std.ArrayListUnmanaged(u64) = .empty,
    cursor: ?u64 = null,
    budget: usize = 0,
    inspected: usize = 0,

    pub fn deinit(self: *PreparationBatch, allocator: std.mem.Allocator) void {
        self.selected.deinit(allocator);
    }

    /// Reserve before discovery. OOM leaves an empty batch and does not move
    /// the cursor. There is no truncated allocation fallback.
    pub fn begin(self: *PreparationBatch, allocator: std.mem.Allocator, budget: usize) !void {
        self.selected.clearRetainingCapacity();
        self.budget = 0;
        self.inspected = 0;
        try self.selected.ensureTotalCapacityPrecise(allocator, budget);
        self.budget = budget;
    }

    fn before(self: *const PreparationBatch, a: u64, b: u64) bool {
        if (self.cursor) |cursor| {
            const a_wraps = a <= cursor;
            const b_wraps = b <= cursor;
            if (a_wraps != b_wraps) return !a_wraps;
        }
        return a < b;
    }

    /// Feed only pending ordinary entities, excluding current/off-graph CMNs
    /// and registered MovementNodes. View order and duplicate memberships do
    /// not change the batch. Work is O(discovered * budget), memory O(highest budget);
    /// discovery is NOT time-bounded just because searches are count-bounded.
    pub fn consider(self: *PreparationBatch, entity: u64) void {
        self.inspected += 1;
        if (self.budget == 0) return;
        var index: usize = 0;
        while (index < self.selected.items.len) : (index += 1) {
            const existing = self.selected.items[index];
            if (existing == entity) return;
            if (self.before(entity, existing)) break;
        }
        if (index >= self.budget) return;
        const old_len = self.selected.items.len;
        if (old_len < self.budget) self.selected.items.len += 1;
        var move = self.selected.items.len - 1;
        while (move > index) : (move -= 1) self.selected.items[move] = self.selected.items[move - 1];
        self.selected.items[index] = entity;
    }

    /// Call at the publication barrier after the entire batch was processed.
    /// Rejected stale results also consume their turn: repeated invalidation
    /// must not prevent progress. Cancelling before execution leaves the cursor.
    pub fn finish(self: *PreparationBatch) void {
        if (self.selected.items.len > 0) self.cursor = self.selected.items[self.selected.items.len - 1];
        self.selected.clearRetainingCapacity();
        self.budget = 0;
    }

    pub fn reset(self: *PreparationBatch) void {
        self.cursor = null;
        self.selected.clearRetainingCapacity();
        self.budget = 0;
        self.inspected = 0;
    }
};
