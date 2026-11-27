# Prepared endpoint implementation: foundation

Design: [Flying Platform RFC #1046](https://github.com/moca-tecnologia/flying-platform-labelle/pull/1046).

This is an additive first slice, not the completed prepared matching API.
Existing navigation and game matching behavior is unchanged.

## Implemented

- Transient CMN publication status: pending, ready, or completed off-graph.
- Input stamp covering world revision, entity ID and generation, effective
  position revision, and graph revision. Revision zero is unpublished;
  entity generation zero and node ID zero are valid values.
- Invalidation retains the old node, distance and last-ready stamp for debugging.
- Publication rejects results whose captured inputs no longer match current
  inputs. An obsolete result cannot overwrite a newer publication. Completed
  off-graph work stays current until its inputs change.
- Explicit distance-table preparation and a const, finite-or-null node-table
  query that never allocates, resolves positions, or rebuilds a dirty table.
  It rejects absent tables, dirty graphs, removed/out-of-range nodes and
  disconnected pairs.

The node-table query is a low-level primitive. Bare node IDs do not establish
endpoint readiness or identity. Controller integration must validate current
registration and generation before calling it. It is not a replacement for
`Controller.distance` yet.

Legacy CMN writers omit the new metadata and therefore create pending records.
Legacy consumers still use the old fields and retain their current behavior.
No current consumer treats these records as prepared endpoints. Do not migrate
matching consumers before the following integration is complete.

## Next integration boundary

1. Add shared effective-position revision propagation to engine position and
   hierarchy mutation paths. `src/game/components_mixin.zig` has `setPosition`,
   `setWorldPosition`, `setParent`, `setParentKeepTransform`, `removeParent` and
   `detachFromParent`; generic component setters and direct ECS writes also need
   coverage. Renderer dirty flags alone do not establish navigation freshness.
   Propagate ancestor changes without walking parent chains in distance queries.
2. Integrate world/entity generations, graph registration and cost-table
   publication in the controller. MovementNode entities use registration directly,
   never self-CMNs. A stale registration cannot fall back to CMN data.
3. Reconcile all CMN writes (`targetPosition`, repath, arrivals) and replace the
   destructive epoch sweep with invalidation retaining the debugging record.
4. Select domain participants through ECS views in stable rotating order with a
   continuation cursor. Snapshot a bounded batch after movement, compute serially,
   validate/publish together before matching. Include discovery cost in measurement.
5. Add entity-level prepared queries, then migrate game matching and diagnostics.
   Missing matches remain normal retries. Known-node bandit placement uses the
   same publication validation. Keep in-flight navigation policy explicit.
6. Measure serial preparation before any threaded execution. Threaded batches
   must publish at the same barrier, with identical selection and late-batch waits.

## Validation

`zig build test spec`: unit tests and all 76 navigation specs pass. Five new
regression tests exercise freshness/publication and the read-only table contract.
This does not establish mutation coverage, rotating-batch fairness, game
integration or WASM performance; those are subsequent acceptance checks.
