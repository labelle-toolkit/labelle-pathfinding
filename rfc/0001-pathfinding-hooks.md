# RFC 0001: Pathfinding Hook System

## Summary

Add a comptime-based hook system to labelle-pathfinding that allows games to observe pathfinding lifecycle events with zero runtime overhead when no handlers are registered.

## Motivation

Games often need to react to pathfinding events for:
- **Debugging/Visualization**: Show the pathfinding process, highlight visited nodes
- **Analytics**: Track pathfinding performance, cache hit rates
- **Game Logic**: Trigger events when paths are found/not found
- **UI Feedback**: Show loading indicators, error messages

Currently, games must poll for results or wrap pathfinding calls. A hook system provides a cleaner, more efficient solution.

## Design

### Hook Types

```zig
pub const PathfindingHook = enum {
    path_requested,   // Pathfinding initiated
    path_found,       // Valid path discovered
    no_path_found,    // No path exists
    node_visited,     // Node visited during search (debug)
    search_complete,  // Search finished (success or failure)
};
```

### Hook Payloads

Each hook has a typed payload with relevant information:

| Hook | Payload Fields |
|------|---------------|
| `path_requested` | source, dest |
| `path_found` | source, dest, cost, path_length |
| `no_path_found` | source, dest, nodes_explored |
| `node_visited` | node, g_score, f_score, from_node |
| `search_complete` | source, dest, success, nodes_explored, path_length, cost |

### API

```zig
// Define hook handlers
const MyPathHooks = struct {
    pub fn path_found(payload: pathfinding.hooks.HookPayload) void {
        const info = payload.path_found;
        std.log.info("Path found! Cost: {d}", .{info.cost});
    }
};

// Create dispatcher
const Dispatcher = pathfinding.hooks.HookDispatcher(MyPathHooks);

// Use with pathfinding algorithm
var astar = pathfinding.AStarWithHooks(Dispatcher).init(allocator);
defer astar.deinit();

// Normal usage - hooks fire automatically
const cost = try astar.findPath(source, dest, &path);
```

### Algorithm Wrappers

New wrapper types that integrate hooks:

- `AStarWithHooks(Dispatcher)` - A* with hook dispatching
- `FloydWarshallWithHooks(Dispatcher)` - Floyd-Warshall with hook dispatching

These wrap the base algorithms and emit hooks at appropriate lifecycle points.

### Zero-Cost Abstraction

When no handler is registered for a hook, the emit call compiles to nothing:

```zig
pub inline fn emit(payload: HookPayload) void {
    switch (payload) {
        inline else => |_, tag| {
            const hook_name = @tagName(tag);
            if (@hasDecl(HookMap, hook_name)) {  // Comptime check
                const handler = @field(HookMap, hook_name);
                handler(payload);
            }
            // No handler = no code generated
        },
    }
}
```

## Integration with labelle-engine

The hook system follows the same patterns as labelle-tasks, enabling:

1. **Generator Detection**: The engine generator can scan for pathfinding hooks in `hooks/` folder
2. **Automatic Wiring**: Generate `PathfindingDispatcher` type from detected hooks
3. **Two-Way Binding**: Games can subscribe to pathfinding events, pathfinding can receive engine events

## Backwards Compatibility

- Existing `AStar` and `FloydWarshall` types unchanged
- New `*WithHooks` types are additive
- Games can migrate incrementally

## Implementation Plan

1. Add `hooks.zig` module with types and dispatcher
2. Add `AStarWithHooks` wrapper in `a_star.zig`
3. Add `FloydWarshallWithHooks` wrapper in `floyd_warshall.zig`
4. Export hooks in `pathfinding.zig`
5. Add tests for hook dispatching
6. Update documentation

## Alternatives Considered

1. **Callback Functions**: Runtime overhead, less type-safe
2. **Event Queue**: Adds allocation, latency
3. **Observer Pattern**: Runtime overhead, more complex

The comptime hook system provides the best balance of type safety, performance, and ergonomics.
