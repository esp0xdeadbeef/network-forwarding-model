# TODO

## Dedicated Transit Lanes ("L2 Lanes")

Status: implemented (always enabled).

What exists today:

- The forwarding-model emits multiple parallel p2p adjacencies between the same staged units when policy/egress intent implies separation.
- `site.transit.dedicatedLanes = true` is always emitted.
- Lane variants are encoded as stable p2p link names (used for addressing + downstream inventory binding).

Remaining work:

- Emit structured lane metadata (not just name/id) so downstream stages do not need to parse link names:
  - `lane.accessUnit = "<s-router-access-...>"`
  - `lane.uplink = "<uplinkName>"` (when applicable)
  - `lane.kind = "downstream-policy" | "policy-upstream" | ...`

- Expand lane derivation beyond access/uplink separation when needed:
  - overlay-specific lanes (when overlays must traverse policy but require dedicated transit)
  - service-scoped lanes (only if the contract model needs physical separation, not just tagging)

## Transit Ordering / Identity

- Keep transit ordering keyed by stable adjacency `id` (not ambiguous node pairs).
- Consider allowing the compiler to optionally emit stable link identities directly (so the forwarding-model does not own naming forever),
  while keeping the forwarding-model as the place that derives which lanes must exist.

