//! Shared types for the labelle-pathfinding module.
//!
//! Contains node data, connection modes, grid helpers, and other types
//! used across the pathfinding engine and its submodules.

const std = @import("std");
const core = @import("labelle-core");

/// Position type from labelle-core for consistency across the labelle ecosystem
pub const Position = core.Position;

/// Backwards compatibility alias (deprecated: use Position instead)
pub const Vec2 = Position;

/// Node identifier type
pub const NodeId = u32;

/// Stair mode for vertical connection traffic control
pub const StairMode = enum {
    /// Not a stair - no vertical connections (default)
    none,
    /// Multi-lane stair - unlimited concurrent usage in any direction
    all,
    /// Directional stair - entities can only use if another is going same direction (or empty)
    direction,
    /// Single-file stair - only one entity can use at a time
    single,
};

/// Log level for controlling pathfinding engine verbosity
pub const LogLevel = enum {
    /// Disable all logging
    none,
    /// Critical failures only
    err,
    /// Recoverable errors and warnings
    warning,
    /// Path requests, entity registration, graph rebuilds
    info,
    /// Detailed operational logs: path steps, stair queues, spatial updates
    debug,

    /// Check if this log level allows messages at the given level
    pub fn allows(self: LogLevel, level: LogLevel) bool {
        return @intFromEnum(self) >= @intFromEnum(level);
    }
};

/// Connection mode for automatic graph building
pub const ConnectionMode = union(enum) {
    /// Top-down games: connect to N closest neighbors in any direction
    omnidirectional: struct {
        max_distance: f32,
        max_connections: u8,
    },
    /// Platformers: connect in 4 cardinal directions
    directional: struct {
        horizontal_range: f32,
        vertical_range: f32,
    },
    /// Building games: horizontal connections + stair-based vertical connections
    building: struct {
        horizontal_range: f32,
        floor_height: f32,
    },
};

/// Node data stored in the graph
pub const NodeData = struct {
    x: f32,
    y: f32,
    stair_mode: StairMode = .none,
};

/// Point with ID for bulk node creation
pub const NodePoint = struct {
    id: NodeId,
    x: f32,
    y: f32,
};

/// Grid connection type for createGrid
pub const GridConnection = enum {
    /// 4-directional movement (up/down/left/right)
    four_way,
    /// 8-directional movement (including diagonals)
    eight_way,
};

/// Configuration for creating a grid of nodes
pub const GridConfig = struct {
    rows: u32,
    cols: u32,
    cell_size: f32,
    offset_x: f32 = 0,
    offset_y: f32 = 0,
    connection: GridConnection = .four_way,
};

/// Helper struct for working with grid-based nodes.
/// Provides conversion utilities between grid coordinates and node IDs/positions.
pub const Grid = struct {
    rows: u32,
    cols: u32,
    cell_size: f32,
    offset_x: f32,
    offset_y: f32,
    start_node_id: NodeId,

    /// Convert grid coordinates to screen/world position
    pub fn toScreen(self: Grid, col: u32, row: u32) Position {
        return Position{
            .x = @as(f32, @floatFromInt(col)) * self.cell_size + self.offset_x,
            .y = @as(f32, @floatFromInt(row)) * self.cell_size + self.offset_y,
        };
    }

    /// Convert grid coordinates to node ID
    pub fn toNodeId(self: Grid, col: u32, row: u32) NodeId {
        return self.start_node_id + row * self.cols + col;
    }

    /// Convert node ID to grid coordinates (col, row)
    pub fn fromNodeId(self: Grid, node_id: NodeId) struct { col: u32, row: u32 } {
        const local_id = node_id - self.start_node_id;
        return .{
            .col = local_id % self.cols,
            .row = local_id / self.cols,
        };
    }

    /// Get the position of a node by its ID
    pub fn nodePosition(self: Grid, node_id: NodeId) Position {
        const coords = self.fromNodeId(node_id);
        return self.toScreen(coords.col, coords.row);
    }

    /// Check if grid coordinates are valid
    pub fn isValid(self: Grid, col: u32, row: u32) bool {
        return col < self.cols and row < self.rows;
    }

    /// Get total number of nodes in the grid
    pub fn nodeCount(self: Grid) u32 {
        return self.rows * self.cols;
    }
};

/// Floyd-Warshall algorithm variant selection
pub const FloydWarshallVariant = enum {
    /// Original implementation (ArrayList-based, compatible with older code)
    legacy,
    /// Optimized with flat memory layout and SIMD (recommended for large graphs)
    optimized_simd,
    /// Optimized with SIMD and multi-threading (best for very large graphs, 100+ nodes)
    optimized_parallel,
};

/// Vertical direction for stair traversal
pub const VerticalDirection = @import("hooks.zig").VerticalDirection;
