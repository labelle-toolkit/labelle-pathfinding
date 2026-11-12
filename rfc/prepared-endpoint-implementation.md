# Prepared endpoint implementation: foundation

Design: [Flying Platform RFC #1046](https://github.com/moca-tecnologia/flying-platform-labelle/pull/1046).

This is a staged implementation, not the completed prepared matching API.
Existing matching APIs remain available. The serial controller phase is opt-in.

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

## Follow-up: rotating bounded selection

`PreparationBatch` now provides world-local execution scratch. Each pass receives
current ECS-derived pending identities, chooses up to the supplied budget in
stable order after the previous cursor, and wraps. View order and duplicate
memberships do not change selection. Deleting the cursor entity does not reset
progress. Newly invalidated entities wait their turn. `finish` advances only at
the publication barrier after the whole selected batch has been processed;
rejected stale results still consume their turn. World changes call `reset`.

There is no default budget or authoritative persistent pending list. Memory is
bounded by the highest requested budget, and allocation failure leaves the batch
empty without moving the cursor. Discovery currently costs O(candidate count ×
budget), including duplicate checks. The helper reports inspected candidates;
it does not claim a wall-time bound. Measure discovery together with snapshots,
searches and publication before choosing the game's budget or optimizing selection.

Five tests cover rotating fairness, deletion/insertion/wrap, duplicates, zero
budget, empty views, OOM and every ordering of a small candidate set. There are
now 81 navigation specs. This helper does not yet discover participants, take
snapshots, search nodes or publish CMNs. Controller integration remains required;
only a pending predicate backed by shared freshness may feed this selector.

## Serial controller phase

The controller now owns batch scratch, snapshots and computed results. Opt in with
`Controller.enableEndpointPreparation(game)` before `advance`. Opt-in graph
validation detects changes in node identity/registration, node world position
(including ancestor motion), stairs and authored links even when node count is
unchanged. The next advance rebuilds the graph when those inputs differ. Missing
metadata or an unavailable graph defers preparation normally. Legacy-only callers
retain the existing graph handling.

After movement, feed the union of the game's matching-participant views to
`prepareEndpointBatch(game, &iterator, budget)`. The union may contain duplicate
entities. Current CMNs and current off-graph results are skipped; MovementNode
entities never enter this ordinary-entity batch. The selected ordinary entities
receive revision tracking through engine#916. All positions are snapshotted before
nearest-node computation, and no CMN is published by this call.

Deinitialize the iterator before the explicit publication phase:

```zig
{
    var participants = game.active_world.ecs_backend.view(.{MatchingParticipant}, .{});
    defer participants.deinit();
    _ = try pathfinder.Controller.prepareEndpointBatch(game, &participants, budget);
}
const stats = pathfinder.Controller.publishEndpointBatch(game);
```

`MatchingParticipant` is an example domain marker, not a new mandatory prefab
component. The game may instead provide an iterator joining its existing domain
views. Call once per frame for the complete participant set; separate per-domain
calls would consume separate budgets and distort rotation. No initial budget is
chosen here: measure discovery, snapshots, searches, graph validation and
publication together before choosing it.

Publication validates the controller/world lifetime, full entity handle, position
revision, graph epoch and graph inputs. It publishes in deterministic selection
order and rejects obsolete results. Rejected results consume their turn, preserving
fairness. `cancelEndpointBatch` discards an unfinished batch without consuming the
turn. A second prepare before publish/cancel returns `PreparationInProgress`;
repeated publication is a no-op. World/controller teardown frees outstanding data.

This is synchronous serial execution. The compute phase reads the current graph
on the main thread; it does not own the immutable graph copy required for worker
threads. These APIs must not be moved onto background threads. Call prepare and
publish in the same logical frame; no scheduler callback should run between them.

Opt-in epoch sweeping invalidates CMNs in place, preserving last-known node data.
Legacy `targetPosition` does not reuse those stale records or completed off-graph
records as a live navigation cache. Other legacy CMN writers can still replace a
record with pending metadata; reconciling those writers and known-node updates
remains part of migration.

Stats expose discovered/pending iterator entries (including duplicate membership),
selected entities, actual nearest-node searches, published/off-graph results and
discarded results. Scratch capacities are reused. OOM before publication exposes
no partial batch and does not consume the cursor; revision registrations made
before an allocation error are harmless and may be reused. Graph-input validation
and discovery are not bounded by the nearest-search budget.

**Not enabled in the game yet:** no gameplay query is switched, and no entity-level
prepared distance API is introduced by this phase. Before rollout, finish the raw
mutation and participant audits, generation-qualified graph/query freshness,
remaining CMN writers/known-node updates, frame-order placement, game query migration
and normal-retry handling for active jobs/raids. In particular, this phase's graph
checks do not constitute a query-time guarantee after arbitrary later mutations.

## Prepared queries and graph dependency freshness

`preparedDistance(game, from, to)` reads only current published endpoints and the
existing FW table. Ordinary entities require a ready CMN with matching world,
entity, position and graph stamps. MovementNode endpoints use the current live
entity registration directly, without a self-CMN. A stale/absent/off-graph or
disconnected endpoint, dirty table, or changed graph dependency returns null.
There are no allocations, parent walks, nearest-node scans, repairs or Euclidean
fallbacks in this query.

Graph construction watches MovementNode/MovementStair/MovementLink mutations and
registered node positions through the engine dependency group. Any subsequent
watched mutation invalidates all prepared queries immediately. Full graph input
validation remains in advance/preparation, outside queries. Direct backend writes
must use the engine invalidation companion; command-level node removal also
invalidates the table. Component-pointer writes are not magically observable.

`endpointPreparationComplete` is a separate lifecycle gate: pending/stale is
false, completed off-graph is true. It does not change the matching null contract.
It lets an active job or raid retry preparation before concluding that no usable
candidate exists. Destroyed targets still need the consumer's existing lifetime
policy.

`publishKnownEndpoint` supports explicit docking/placement. It validates actual
world-space position against the registered node, snap radius and Y filter, then
publishes the current stamp. It rejects MovementNode recipients and cannot repair
a stale graph. Opted-in `requestRepath` invalidates for the bounded phase instead
of scanning synchronously. Legacy navigation commands remain available separately.
