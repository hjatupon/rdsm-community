# TFTree — Transform Tree

## Key Types
- `TFTree` (actor) — insert(parent:child:transform:at:isStatic:), lookup(from:to:at:), frames, rates, edgesWithMetadata
- `TFGraph` — dynamic edges (temporal [TFSample]), static edges (permanent), interpolation, sliding window Hz
- `TFTransform { translation: SIMD3<Double>, rotation: simd_quatd }` — composition via `then()`, inverse
- `TFAgeStatus` — fresh (< green), aging (< yellow), stale enum with color mapping

## Edge Convention (CRITICAL)
- Stored: parent→child direction. The transform `t` expresses child frame in parent frame.
- Lookup: source→target via BFS. Each step: `contrib = step.forward ? t.inverse : t`
  - Forward step (parent→child): use t.inverse
  - Backward step (child→parent): use t directly
- This was a critical bug fix — do NOT flip.

## Interpolation
- Exact timestamp match → return that sample
- Before first → nil (no data)
- After last → last known (extrapolate)
- Between → SLERP (rotation) + linear (translation)

## Gotchas
- Frame ID normalization: strips leading `/` so `/base_link` == `base_link`
- historyDurationNs: default 10s (samples older than this pruned)
- Path cache invalidated on topology change (new frame appears)
