# Serial endpoint preparation integration

This harness uses `labelle-engine`'s Game with its headless ECS backend and the
actual pathfinder controller. It does not recreate Game, hierarchy, revision or
controller behavior in a test double. It is separate from the library's regular
unit/spec targets so using the published pathfinder does not gain an engine
runtime dependency.

Required sibling layout:

```
labelle-core/
labelle-engine/       # engine#916, b93dafd1295fe5324be70c6249fc4687a78b8fe3
labelle-pathfinding/
```

With Zig 0.16.0, from `labelle-pathfinding`:

```
zig build test --build-file tests/integration/build.zig --summary all
```

The ordinary `zig build test spec` targets remain required. CI runs both and pins
the engine commit supplying position revisions. Replace that pin with the released
API when engine#916 lands. This suite validates the controller/engine lifecycle;
it does not measure WASM performance or replace actual-game acceptance tests.
