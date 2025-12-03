# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Run unit tests (built-in Zig tests)
zig build test

# Run zspec behavior tests
zig build spec

# Run examples
zig build run-basic      # Basic pathfinding example (start here)
zig build run-game       # Game integration with callbacks
zig build run-platformer # Platformer with directional connections
zig build run-engine     # Full engine features demo
zig build run-building   # Multi-floor building with stairs
zig build run-examples   # Run all examples
```

## Architecture

This is a Zig pathfinding library for games. It requires Zig 0.15.2+.

### Core Components

- **PathfindingEngine** (`src/engine.zig`): Self-contained engine that owns entity positions. Games query the engine for positions rather than managing them directly. Configured via comptime Config struct with `Entity` and `Context` types.

- **Floyd-Warshall** (`src/floyd_warshall.zig`): Precomputes all-pairs shortest paths. Used internally by PathfindingEngine. Best for dense graphs with frequent queries between many node pairs.

- **A*** (`src/a_star.zig`): Single-source shortest path with pluggable heuristics. Better for large sparse graphs or dynamic scenarios.

- **QuadTree** (`src/quad_tree.zig`): Spatial indexing for O(log n) entity and node lookups. Used for `getEntitiesInRadius`, `getEntitiesInRect`, etc.

### Connection Modes

The engine supports three graph connection strategies:
- `omnidirectional`: Top-down games (connect to N closest neighbors)
- `directional`: Platformers (4-direction: left/right/up/down)
- `building`: Multi-floor buildings (horizontal + stair-based vertical only)

### Stair Traffic Control

For building mode, stairs can have traffic modes:
- `.none`: Not a stair
- `.all`: Multi-lane, unlimited concurrent usage
- `.direction`: Multiple entities allowed if same direction
- `.single`: Single-file, one entity at a time

Waiting areas can be defined for entities queuing at busy stairs.

### Legacy ECS Support

`src/components.zig` and `src/movement_node_controller.zig` provide zig-ecs integration for legacy codebases that manage positions externally.

## Testing

Tests are in `tests/` using zspec. Each `*_spec.zig` file tests a specific module. The `tests/spec_tests.zig` aggregates all specs.
