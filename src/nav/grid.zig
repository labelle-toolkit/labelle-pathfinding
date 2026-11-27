const std = @import("std");
const algo = @import("../grid_astar.zig");
const components = @import("components.zig");
const Position = @import("types.zig").Position;
const Cell = algo.Cell;
const Bounds = algo.Bounds;
const Allocator = std.mem.Allocator;

pub const Footprint = struct {
    obstacle: ?Bounds = null,
    terrain: ?Bounds = null,
    cost: u8 = 0,
};

test "smoothing uses distance traveled within each tile and skips recentering" {
    const a = std.testing.allocator;
    var grid = try Grid.init(a, .{ .cell = 10, .cols = 4, .rows = 3 });
    defer grid.deinit(a);
    const route = [_]Cell{ .{ .col = 0, .row = 0 }, .{ .col = 1, .row = 1 }, .{ .col = 2, .row = 1 } };
    const from = Position{ .x = 7, .y = 5 };
    const goal = grid.center(route[2]);
    const points = try grid.waypoints(a, &route, from);
    defer a.free(points);
    try std.testing.expectEqualSlices(Position, &.{goal}, points);

    // The shortcut traverses an expensive cell the original diagonal only
    // touches at a corner. Cost alone is enough to keep it off the route.
    grid.search.tiles[1].cost = 100;
    const detour = try grid.waypoints(a, &route, grid.center(route[0]));
    defer a.free(detour);
    try std.testing.expectEqualSlices(Position, &.{ grid.center(route[1]), goal }, detour);
}

pub const Walk = struct {
    points: []Position,
    next: usize = 0,
    adjacent: ?u64 = null,
    goal: Cell,
    escape_from: ?Cell = null,
};

pub const Grid = struct {
    config: components.NavGrid,
    search: algo.GridAStar,
    scratch: []u32,
    changed: []bool,
    footprints: std.AutoHashMapUnmanaged(u64, Footprint) = .empty,

    pub fn init(a: Allocator, config: components.NavGrid) !Grid {
        if (!std.math.isFinite(config.cell) or config.cell <= 0 or
            !std.math.isFinite(config.origin_x) or !std.math.isFinite(config.origin_y) or
            !std.math.isFinite(config.agent_radius) or config.agent_radius < 0 or
            config.cols == 0 or config.rows == 0) return error.InvalidGrid;
        const count = try std.math.mul(u32, config.cols, config.rows);
        const tiles = try a.alloc(algo.Tile, count);
        errdefer a.free(tiles);
        @memset(tiles, .{ .cost = config.default_cost });
        const scratch = try a.alloc(u32, count);
        errdefer a.free(scratch);
        const grid: Grid = .{
            .config = config,
            .search = .{ .cols = config.cols, .rows = config.rows, .tiles = tiles },
            .scratch = scratch,
            .changed = try a.alloc(bool, count),
        };
        errdefer a.free(grid.changed);
        const last = grid.all().max;
        const first: Cell = .{ .col = 0, .row = 0 };
        if (!std.meta.eql(grid.at(grid.center(first)), @as(?Cell, first)) or
            !std.meta.eql(grid.at(grid.center(last)), @as(?Cell, last))) return error.InvalidGrid;
        @memset(grid.changed, false);
        return grid;
    }

    pub fn deinit(self: *Grid, a: Allocator) void {
        self.footprints.deinit(a);
        a.free(self.search.tiles);
        a.free(self.scratch);
        a.free(self.changed);
    }

    pub fn all(self: Grid) Bounds {
        return .{ .min = .{ .col = 0, .row = 0 }, .max = .{ .col = self.config.cols - 1, .row = self.config.rows - 1 } };
    }

    fn local(self: Grid, p: Position) [2]f64 {
        return .{
            (@as(f64, p.x) - self.config.origin_x) / self.config.cell,
            (@as(f64, p.y) - self.config.origin_y) / self.config.cell,
        };
    }

    pub fn at(self: Grid, p: Position) ?Cell {
        const v = self.local(p);
        if (!(v[0] >= 0 and v[0] < @as(f64, @floatFromInt(self.config.cols)) and
            v[1] >= 0 and v[1] < @as(f64, @floatFromInt(self.config.rows)))) return null;
        return .{ .col = @intFromFloat(v[0]), .row = @intFromFloat(v[1]) };
    }

    pub fn center(self: Grid, c: Cell) Position {
        return .{
            .x = @floatCast(@as(f64, self.config.origin_x) + (@as(f64, @floatFromInt(c.col)) + 0.5) * self.config.cell),
            .y = @floatCast(@as(f64, self.config.origin_y) + (@as(f64, @floatFromInt(c.row)) + 0.5) * self.config.cell),
        };
    }

    pub fn stampBounds(self: Grid, pos: Position, rect: anytype, grow: f32) ?Bounds {
        if (!(rect.width > 0 and rect.height > 0)) return null;
        const p = self.local(.{ .x = pos.x + rect.offset_x, .y = pos.y + rect.offset_y });
        const hx = (@as(f64, rect.width) / 2 + grow) / self.config.cell;
        const hy = (@as(f64, rect.height) / 2 + grow) / self.config.cell;
        const cols: f64 = @floatFromInt(self.config.cols);
        const rows: f64 = @floatFromInt(self.config.rows);
        const left = @max(0, @floor(p[0] - hx));
        const top = @max(0, @floor(p[1] - hy));
        const right = @min(cols, @ceil(p[0] + hx));
        const bottom = @min(rows, @ceil(p[1] + hy));
        if (!std.math.isFinite(p[0]) or !std.math.isFinite(p[1]) or
            !std.math.isFinite(hx) or !std.math.isFinite(hy) or !(left < right and top < bottom)) return null;
        return .{
            .min = .{ .col = @intFromFloat(left), .row = @intFromFloat(top) },
            .max = .{ .col = @intFromFloat(right - 1), .row = @intFromFloat(bottom - 1) },
        };
    }

    pub fn footprint(self: Grid, ecs: anytype, entity: anytype) Footprint {
        if (!ecs.entityExists(entity)) return .{};
        const pos = ecs.getComponent(entity, Position) orelse return .{};
        const obstacle = ecs.getComponent(entity, components.NavObstacle);
        const terrain = ecs.getComponent(entity, components.NavCost);
        return .{
            .obstacle = if (obstacle) |r| self.stampBounds(pos.*, r.*, self.config.agent_radius) else null,
            .terrain = if (terrain) |r| self.stampBounds(pos.*, r.*, 0) else null,
            .cost = if (terrain) |r| r.cost else 0,
        };
    }

    pub fn stamp(self: *Grid, bounds: Bounds) bool {
        // Build replacement values only inside the dirty rectangle. Each
        // cached footprint contributes only to its intersection with it.
        const blocked_bit: u32 = 1 << 8;
        const terrain_bit: u32 = 1 << 9;
        for (bounds.min.row..@as(usize, bounds.max.row) + 1) |row| {
            const first = row * self.config.cols + bounds.min.col;
            @memset(self.scratch[first .. first + bounds.max.col - bounds.min.col + 1], 0);
        }
        var it = self.footprints.valueIterator();
        while (it.next()) |f| {
            if (f.obstacle) |rect| {
                if (intersect(bounds, rect)) |b| {
                    for (b.min.row..@as(usize, b.max.row) + 1) |row| {
                        for (b.min.col..@as(usize, b.max.col) + 1) |col| self.scratch[row * self.config.cols + col] |= blocked_bit;
                    }
                }
            }
            if (f.terrain) |rect| {
                if (intersect(bounds, rect)) |b| {
                    for (b.min.row..@as(usize, b.max.row) + 1) |row| {
                        for (b.min.col..@as(usize, b.max.col) + 1) |col| {
                            const tile = &self.scratch[row * self.config.cols + col];
                            tile.* = (tile.* & blocked_bit) | terrain_bit | @max(tile.* & 255, f.cost);
                        }
                    }
                }
            }
        }
        var any_changed = false;
        for (bounds.min.row..@as(usize, bounds.max.row) + 1) |row| {
            for (bounds.min.col..@as(usize, bounds.max.col) + 1) |col| {
                const i = row * self.config.cols + col;
                const value = self.scratch[i];
                const blocked = value & blocked_bit != 0;
                const cost: u8 = if (value & terrain_bit != 0) @truncate(value) else self.config.default_cost;
                const tile = &self.search.tiles[i];
                self.changed[i] = tile.blocked != blocked or tile.cost != cost;
                any_changed = any_changed or self.changed[i];
                tile.blocked = blocked;
                tile.cost = cost;
            }
        }
        return any_changed;
    }

    fn intersect(a: Bounds, b: Bounds) ?Bounds {
        const out: Bounds = .{
            .min = .{ .col = @max(a.min.col, b.min.col), .row = @max(a.min.row, b.min.row) },
            .max = .{ .col = @min(a.max.col, b.max.col), .row = @min(a.max.row, b.max.row) },
        };
        return if (out.min.col <= out.max.col and out.min.row <= out.max.row) out else null;
    }

    pub fn region(self: Grid, c: Cell) u32 {
        return self.search.tiles[self.search.index(c)].region;
    }

    pub fn goal(self: Grid, start: Cell, requested: Cell, snap: bool) ?Cell {
        const r = self.region(start);
        if (r == 0) return null;
        if (self.search.free(requested)) return if (self.region(requested) == r) requested else null;
        if (!snap) return null;
        var best: ?Cell = null;
        var best_dist: u128 = std.math.maxInt(u128);
        for (self.search.tiles, 0..) |t, i| {
            if (t.region != r) continue;
            const c = self.search.cell(@intCast(i));
            const dx: u128 = @max(c.col, requested.col) - @min(c.col, requested.col);
            const dy: u128 = @max(c.row, requested.row) - @min(c.row, requested.row);
            const d = dx * dx + dy * dy;
            if (d < best_dist) {
                best = c;
                best_dist = d;
            }
        }
        return best;
    }

    pub fn adjacent(self: Grid, a: Allocator, start: Cell, id: u64) ![]Cell {
        const r = self.region(start);
        const bounds = (self.footprints.get(id) orelse return a.alloc(Cell, 0)).obstacle orelse return a.alloc(Cell, 0);
        var list: std.ArrayList(Cell) = .empty;
        errdefer list.deinit(a);
        const left = bounds.min.col -| 1;
        const right = @min(bounds.max.col + 1, self.config.cols - 1);
        const top = bounds.min.row -| 1;
        const bottom = @min(bounds.max.row + 1, self.config.rows - 1);
        for (top..@as(usize, bottom) + 1) |row| {
            for (left..@as(usize, right) + 1) |col| {
                const c: Cell = .{ .col = @intCast(col), .row = @intCast(row) };
                if (bounds.contains(c) or (col >= bounds.min.col and col <= bounds.max.col) ==
                    (row >= bounds.min.row and row <= bounds.max.row)) continue;
                if (r != 0 and self.region(c) == r) try list.append(a, c);
            }
        }
        return list.toOwnedSlice(a);
    }

    pub fn reachableAdjacent(self: Grid, start: Cell, id: u64) bool {
        const r = self.region(start);
        if (r == 0) return false;
        const bounds = (self.footprints.get(id) orelse return false).obstacle orelse return false;
        for (bounds.min.col..@as(usize, bounds.max.col) + 1) |col| {
            if (bounds.min.row > 0 and self.region(.{ .col = @intCast(col), .row = bounds.min.row - 1 }) == r) return true;
            if (bounds.max.row + 1 < self.config.rows and self.region(.{ .col = @intCast(col), .row = bounds.max.row + 1 }) == r) return true;
        }
        for (bounds.min.row..@as(usize, bounds.max.row) + 1) |row| {
            if (bounds.min.col > 0 and self.region(.{ .col = bounds.min.col - 1, .row = @intCast(row) }) == r) return true;
            if (bounds.max.col + 1 < self.config.cols and self.region(.{ .col = bounds.max.col + 1, .row = @intCast(row) }) == r) return true;
        }
        return false;
    }

    const Segment = struct { valid: bool = true, dirty: bool = false, cost: f64 = 0 };

    /// Traverse continuous coordinates, including both support cells at a
    /// corner crossing. Used for smoothing and for route invalidation.
    pub fn segment(self: Grid, from: Position, to: Position, dirty: ?Bounds) Segment {
        return self.walkSegment(from, to, dirty, null);
    }

    /// Escape may cross the occupied starting cell into one free axial
    /// neighbor. All later cells and corner supports still have to be free.
    pub fn walkSegment(self: Grid, from: Position, to: Position, dirty: ?Bounds, escape_from: ?Cell) Segment {
        var current = self.at(from) orelse return .{ .valid = false, .dirty = true };
        const end = self.at(to) orelse return .{ .valid = false, .dirty = true };
        const p = self.local(from);
        const q = self.local(to);
        const dx = q[0] - p[0];
        const dy = q[1] - p[1];
        const sx: i64 = if (dx < 0) -1 else 1;
        const sy: i64 = if (dy < 0) -1 else 1;
        const length = @sqrt(dx * dx + dy * dy);
        var previous_t: f64 = 0;
        var result: Segment = .{};
        self.checkCell(current, dirty, &result);
        if (escape_from) |cell| {
            if (std.meta.eql(cell, current)) result.valid = true;
        }
        while (!std.meta.eql(current, end)) {
            const x: f64 = @floatFromInt(current.col);
            const y: f64 = @floatFromInt(current.row);
            const tx = if (current.col != end.col) (x + @as(f64, if (sx > 0) 1 else 0) - p[0]) / dx else std.math.inf(f64);
            const ty = if (current.row != end.row) (y + @as(f64, if (sy > 0) 1 else 0) - p[1]) / dy else std.math.inf(f64);
            const corner = @abs(tx - ty) <= 1e-12;
            const t = std.math.clamp(@min(tx, ty), previous_t, 1);
            result.cost += (t - previous_t) * self.cellWeight(current);
            previous_t = t;
            const next_col: u32 = if (corner or tx < ty) @intCast(@as(i64, current.col) + sx) else current.col;
            const next_row: u32 = if (corner or ty < tx) @intCast(@as(i64, current.row) + sy) else current.row;
            if (corner) {
                self.checkCell(.{ .col = next_col, .row = current.row }, dirty, &result);
                self.checkCell(.{ .col = current.col, .row = next_row }, dirty, &result);
            }
            current = .{ .col = next_col, .row = next_row };
            self.checkCell(current, dirty, &result);
        }
        result.cost = (result.cost + (1 - previous_t) * self.cellWeight(end)) * length;
        return result;
    }

    fn cellWeight(self: Grid, c: Cell) f64 {
        return @floatFromInt(self.search.tiles[self.search.index(c)].cost);
    }

    fn edgeCost(self: Grid, a: Cell, b: Cell) f64 {
        // Center-to-center, half the distance lies inside each cell.
        const length: f64 = if (a.col != b.col and a.row != b.row) @sqrt(2.0) else 1;
        return length * (self.cellWeight(a) + self.cellWeight(b)) / 2;
    }

    pub fn escapeNeighbors(self: Grid, cell: Cell) [4]?Cell {
        const candidates: [4]?Cell = .{
            if (cell.col > 0) .{ .col = cell.col - 1, .row = cell.row } else null,
            if (cell.col + 1 < self.config.cols) .{ .col = cell.col + 1, .row = cell.row } else null,
            if (cell.row > 0) .{ .col = cell.col, .row = cell.row - 1 } else null,
            if (cell.row + 1 < self.config.rows) .{ .col = cell.col, .row = cell.row + 1 } else null,
        };
        var free = candidates;
        for (&free) |*candidate| {
            if (candidate.*) |c| {
                if (!self.search.free(c)) candidate.* = null;
            }
        }
        return free;
    }

    fn checkCell(self: Grid, c: Cell, bounds: ?Bounds, out: *Segment) void {
        out.valid = out.valid and self.search.free(c);
        if (bounds) |b| out.dirty = out.dirty or (b.contains(c) and self.changed[self.search.index(c)]);
    }

    pub fn waypoints(self: Grid, a: Allocator, route: []const Cell, from: Position) ![]Position {
        var points: std.ArrayList(Position) = .empty;
        errdefer points.deinit(a);
        const first = self.center(route[0]);
        if (route.len == 1) {
            if (!std.meta.eql(from, first)) try points.append(a, first);
            return points.toOwnedSlice(a);
        }
        var origin = from;
        var anchor: usize = 0;
        while (anchor + 1 < route.len) {
            var best = anchor;
            var original = self.segment(origin, self.center(route[anchor]), null).cost;
            for (anchor + 1..route.len) |j| {
                const previous = route[j - 1];
                const c = route[j];
                original += self.edgeCost(previous, c);
                const candidate = self.segment(origin, self.center(c), null);
                if (candidate.valid and candidate.cost <= original + 1e-9 * @max(1, original)) best = j;
                // Bound smoothing work per anchor on long, winding routes.
                if (j - anchor >= 64) break;
            }
            // If the off-center start cannot safely reach the next waypoint,
            // go through its own cell center before taking the first edge.
            if (best == anchor and std.meta.eql(origin, self.center(route[anchor]))) best += 1;
            origin = self.center(route[best]);
            try points.append(a, origin);
            anchor = best;
        }
        return points.toOwnedSlice(a);
    }
};
