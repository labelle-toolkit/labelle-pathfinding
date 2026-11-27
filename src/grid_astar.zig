const std = @import("std");

pub const Cell = struct { col: u32, row: u32 };
pub const Bounds = struct {
    min: Cell,
    max: Cell,

    pub fn contains(self: Bounds, cell: Cell) bool {
        return cell.col >= self.min.col and cell.col <= self.max.col and
            cell.row >= self.min.row and cell.row <= self.max.row;
    }

    pub fn merge(a: Bounds, b: Bounds) Bounds {
        return .{
            .min = .{ .col = @min(a.min.col, b.min.col), .row = @min(a.min.row, b.min.row) },
            .max = .{ .col = @max(a.max.col, b.max.col), .row = @max(a.max.row, b.max.row) },
        };
    }
};

pub const Tile = struct {
    blocked: bool = false,
    cost: u8 = 10,
    region: u32 = 0,
};

/// An implicit, weighted eight-connected grid. Costs are fixed-point:
/// an axial step costs 10 * tile.cost and a diagonal costs 14 * tile.cost.
pub const GridAStar = struct {
    cols: u32,
    rows: u32,
    tiles: []Tile,
    min_cost: u8 = 0,

    pub fn index(self: GridAStar, c: Cell) u32 {
        return c.row * self.cols + c.col;
    }

    pub fn cell(self: GridAStar, i: u32) Cell {
        return .{ .col = i % self.cols, .row = i / self.cols };
    }

    pub fn inside(self: GridAStar, c: Cell) bool {
        return c.col < self.cols and c.row < self.rows;
    }

    pub fn free(self: GridAStar, c: Cell) bool {
        return self.inside(c) and !self.tiles[self.index(c)].blocked;
    }

    const Step = struct { cell: Cell, diagonal: bool };
    fn step(self: GridAStar, from: Cell, dx: i2, dy: i2) ?Step {
        const x = @as(i64, from.col) + dx;
        const y = @as(i64, from.row) + dy;
        if (x < 0 or y < 0) return null;
        const to: Cell = .{ .col = @intCast(x), .row = @intCast(y) };
        if (!self.free(to)) return null;
        const diagonal = dx != 0 and dy != 0;
        if (diagonal and (!self.free(.{ .col = to.col, .row = from.row }) or
            !self.free(.{ .col = from.col, .row = to.row }))) return null;
        return .{ .cell = to, .diagonal = diagonal };
    }

    const offsets = [_][2]i2{ .{ 1, 0 }, .{ 0, 1 }, .{ -1, 0 }, .{ 0, -1 }, .{ 1, 1 }, .{ -1, 1 }, .{ -1, -1 }, .{ 1, -1 } };

    /// Scratch must hold one index per tile. Zero denotes a blocked tile.
    pub fn labelRegions(self: *GridAStar, scratch: []u32) void {
        self.min_cost = 255;
        for (self.tiles) |*tile| {
            tile.region = 0;
            if (!tile.blocked) self.min_cost = @min(self.min_cost, tile.cost);
        }
        var region: u32 = 0;
        for (self.tiles, 0..) |*tile, i| {
            if (tile.blocked or tile.region != 0) continue;
            region += 1;
            tile.region = region;
            scratch[0] = @intCast(i);
            var head: usize = 0;
            var tail: usize = 1;
            while (head < tail) : (head += 1) {
                const from = self.cell(scratch[head]);
                for (offsets) |d| {
                    const next = self.step(from, d[0], d[1]) orelse continue;
                    const j = self.index(next.cell);
                    if (self.tiles[j].region != 0) continue;
                    self.tiles[j].region = region;
                    scratch[tail] = j;
                    tail += 1;
                }
            }
        }
    }

    const Entry = struct { i: u32, cost: u64, score: u64 };
    fn compare(_: void, a: Entry, b: Entry) std.math.Order {
        return switch (std.math.order(a.score, b.score)) {
            .eq => std.math.order(a.i, b.i),
            else => |order| order,
        };
    }

    fn heuristic(self: GridAStar, c: Cell, bounds: Bounds) u64 {
        const dx: u64 = @max(c.col, bounds.min.col) - @min(c.col, bounds.max.col);
        const dy: u64 = @max(c.row, bounds.min.row) - @min(c.row, bounds.max.row);
        return (10 * @max(dx, dy) + 4 * @min(dx, dy)) * self.min_cost;
    }

    pub const Route = struct { cells: []Cell, cost: u64 };
    const Visit = struct { cost: u64 = std.math.maxInt(u64), parent: u32 = 0 };

    /// Find the cheapest reachable goal. The returned cells include start
    /// and goal. The caller owns the slice.
    pub fn search(self: GridAStar, a: std.mem.Allocator, start: Cell, goals: []const Cell) !?Route {
        var current = self;
        current.min_cost = 255;
        for (self.tiles) |tile| {
            if (!tile.blocked) current.min_cost = @min(current.min_cost, tile.cost);
        }
        return current.searchImpl(a, start, goals, false);
    }

    /// Fast path for a grid labeled by `labelRegions` since its last edit.
    pub fn searchPrepared(self: GridAStar, a: std.mem.Allocator, start: Cell, goals: []const Cell) !?Route {
        return self.searchImpl(a, start, goals, true);
    }

    fn searchImpl(self: GridAStar, a: std.mem.Allocator, start: Cell, goals: []const Cell, prepared: bool) !?Route {
        if (!self.free(start) or goals.len == 0) return null;
        const visits = try a.alloc(Visit, self.tiles.len);
        defer a.free(visits);
        @memset(visits, .{});
        const goal_mask = try a.alloc(bool, self.tiles.len);
        defer a.free(goal_mask);
        @memset(goal_mask, false);
        var bounds: ?Bounds = null;
        const region = self.tiles[self.index(start)].region;
        for (goals) |goal| {
            if (!self.free(goal) or (prepared and self.tiles[self.index(goal)].region != region)) continue;
            goal_mask[self.index(goal)] = true;
            const point: Bounds = .{ .min = goal, .max = goal };
            bounds = if (bounds) |previous| previous.merge(point) else point;
        }
        const goal_bounds = bounds orelse return null;
        var queue: std.PriorityQueue(Entry, void, compare) = .initContext({});
        defer queue.deinit(a);
        const first = self.index(start);
        visits[first].cost = 0;
        try queue.push(a, .{ .i = first, .cost = 0, .score = self.heuristic(start, goal_bounds) });
        while (queue.pop()) |entry| {
            if (entry.cost != visits[entry.i].cost) continue;
            if (goal_mask[entry.i]) {
                var count: usize = 1;
                var cursor = entry.i;
                while (cursor != first) : (count += 1) cursor = visits[cursor].parent;
                const route = try a.alloc(Cell, count);
                cursor = entry.i;
                while (count > 0) {
                    count -= 1;
                    route[count] = self.cell(cursor);
                    if (cursor != first) cursor = visits[cursor].parent;
                }
                return .{ .cells = route, .cost = entry.cost };
            }
            const from = self.cell(entry.i);
            for (offsets) |d| {
                const next = self.step(from, d[0], d[1]) orelse continue;
                const j = self.index(next.cell);
                const scale: u64 = if (next.diagonal) 14 else 10;
                const cost = entry.cost + scale * self.tiles[j].cost;
                if (cost >= visits[j].cost) continue;
                visits[j] = .{ .cost = cost, .parent = entry.i };
                try queue.push(a, .{ .i = j, .cost = cost, .score = cost + self.heuristic(next.cell, goal_bounds) });
            }
        }
        return null;
    }
};

test "weighted route avoids expensive cells and diagonal support controls connectivity" {
    const a = std.testing.allocator;
    var tiles = [_]Tile{.{}} ** 6;
    var grid: GridAStar = .{ .cols = 3, .rows = 2, .tiles = &tiles };
    var scratch: [6]u32 = undefined;
    tiles[1].cost = 100;
    grid.labelRegions(&scratch);
    const start: Cell = .{ .col = 0, .row = 0 };
    const goal: Cell = .{ .col = 2, .row = 0 };
    const route = (try grid.search(a, start, &.{goal})).?;
    defer a.free(route.cells);
    try std.testing.expectEqual(@as(u64, 280), route.cost);
    tiles[1].blocked = true;
    tiles[3].blocked = true;
    grid.labelRegions(&scratch);
    try std.testing.expect((try grid.search(a, start, &.{goal})) == null);
}

test "standalone search sees cost and topology edits without relabeling" {
    const a = std.testing.allocator;
    var tiles = [_]Tile{.{ .cost = 100 }} ** 6;
    var grid: GridAStar = .{ .cols = 3, .rows = 2, .tiles = &tiles };
    var scratch: [6]u32 = undefined;
    tiles[2].blocked = true;
    grid.labelRegions(&scratch);
    tiles[2].blocked = false;
    tiles[1].cost = 10;
    tiles[2].cost = 1;
    tiles[4].cost = 1;
    const route = (try grid.search(a, .{ .col = 0, .row = 0 }, &.{.{ .col = 2, .row = 0 }})).?;
    defer a.free(route.cells);
    try std.testing.expectEqual(@as(u64, 28), route.cost);
}
