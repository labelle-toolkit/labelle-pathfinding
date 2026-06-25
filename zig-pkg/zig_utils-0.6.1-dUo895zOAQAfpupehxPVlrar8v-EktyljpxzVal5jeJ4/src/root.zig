// zig-utils - Standalone utilities for Zig
// No external dependencies, only std

pub const vector = @import("vector.zig");
pub const Position = vector.Position;
pub const PositionI = vector.PositionI;

pub const quad_tree = @import("quad_tree.zig");
pub const QuadTree = quad_tree.QuadTree;
pub const QuadTreeConfig = quad_tree.QuadTreeConfig;
pub const EntityPoint = quad_tree.EntityPoint;
pub const Rectangle = quad_tree.Rectangle;

pub const sweep_and_prune = @import("sweep_and_prune.zig");
pub const SweepAndPrune = sweep_and_prune.SweepAndPrune;
pub const AABB = sweep_and_prune.AABB;
pub const CollisionPair = sweep_and_prune.CollisionPair;
pub const sweepAndPruneSimple = sweep_and_prune.sweepAndPrune;

pub const sparse_set = @import("sparse_set.zig");
pub const SparseSet = sparse_set.SparseSet;

pub const z_index_buckets = @import("z_index_buckets.zig");
pub const ZIndexBuckets = z_index_buckets.ZIndexBuckets;

pub const zon = @import("zon_coercion.zig");
pub const coerceValue = zon.coerceValue;
pub const buildStruct = zon.buildStruct;
pub const tupleToSlice = zon.tupleToSlice;
pub const mergeStructs = zon.mergeStructs;

pub const hooks = @import("hook_dispatcher.zig");
pub const HookDispatcher = hooks.HookDispatcher;
pub const EmptyDispatcher = hooks.EmptyDispatcher;
pub const MergeHooks = hooks.MergeHooks;

// Graph algorithms
pub const floyd_warshall = @import("floyd_warshall.zig");
pub const FloydWarshall = floyd_warshall.FloydWarshall;

pub const floyd_warshall_optimized = @import("floyd_warshall_optimized.zig");
pub const FloydWarshallOptimized = floyd_warshall_optimized.FloydWarshallOptimized;
pub const FloydWarshallConfig = floyd_warshall_optimized.Config;
pub const FloydWarshallParallel = floyd_warshall_optimized.FloydWarshallParallel;
pub const FloydWarshallSimd = floyd_warshall_optimized.FloydWarshallSimd;
pub const FloydWarshallScalar = floyd_warshall_optimized.FloydWarshallScalar;

pub const a_star = @import("a_star.zig");
pub const AStar = a_star.AStar;

pub const heuristics = @import("heuristics.zig");
pub const Heuristic = heuristics.Heuristic;

// Backwards compatibility alias (deprecated)
pub const Vector2 = Position;
