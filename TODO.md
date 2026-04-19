# TODO

## Policy-Driven Dedicated Transit Links ("L2 Lanes")

### Problem

Today, the forwarding model (and its p2p allocator) assumes there is at most one p2p transit adjacency per node-pair.
This makes it impossible to guarantee "dedicated links" between stages when intent/policy implies separation.

Examples that cannot be expressed safely today:

- Multi-WAN: policy/upstream-selection should have distinct transit segments per uplink (and often per access class).
- Per-access-box separation: traffic from `s-router-access-client` should traverse policy over a dedicated L2 segment that cannot be shared with unrelated classes.

As a result, `intent.nix` cannot currently *guarantee* the L2 separation semantics implied by routing/policy intent.

### Goal

Make L2 segmentation an explicit, deterministic artifact of upstream intent:

`intent (relations / routing intent) -> forwarding model derives required L2 lanes -> CPM binds lanes via inventory -> renderers only consume CPM`

The renderer must not choose "modes" or invent segmentation.

### What drives lanes (common-sense rule)

If `intent.nix` says traffic is allowed to take a particular egress (uplink/overlay/etc), that *implicitly requires* a distinct forwarding path.
In a staged architecture where policy enforcement is tied to stage boundaries, that can (and often should) imply distinct L2 segments
so that:

- policy can be applied to the correct ingress/egress lane
- “rogue” uplinks/cores cannot affect unrelated lanes
- later routing protocol choices (static/BGP/other) do not change the security boundary

In other words: “route/egress intent impacts L2”.

### Desired behavior (conceptual)

For a multi-uplink site:

- `access -> downstream-selector`: downstream-selector chooses the correct ingress lane for the access box / class
- `downstream-selector -> policy`: policy enforces on the specific lane (per-class transit)
- `policy -> upstream-selector`: dedicated lane(s) per allowed uplink-set / egress class
- `upstream-selector -> core-*`: per-uplink lanes to exit-capable cores (or per-uplink-per-core where needed)
- `core-*`: cares about upstream reachability (up/down), not policy or lane derivation

### Approach

Introduce a first-class "lane" identity for transit edges and allow multiple p2p links between the same node pair.

Key points:

- Lanes are derived in this stage from explicit upstream intent (relations, egress intent, overlays, etc).
- Each lane has a stable identity (used for deterministic addressing + inventory binding downstream).
- Transit ordering/validation must operate on lane edges (not only node pairs).

### Implementation sketch

1) Represent p2p requirements as link specs (not bare node pairs)

- New internal representation (example):
  - `{ a = "s-router-policy"; b = "s-router-upstream-selector"; lane = "lane::client::wan"; }`
- Deterministic sort key: `(stageRank(aRole), a, b, lane)`
- Back-compat: if input is `[ "a" "b" ]`, synthesize `lane = "lane::default"` for that pair.

2) Update p2p allocator to accept duplicates per node pair

- `lib/p2p/alloc.nix`:
  - remove the "duplicate logical p2p link" restriction (currently keyed by node pair)
  - allocate per *lane spec* instead
  - require a stable link `name/id` derived from the lane spec (not just `"p2p-${a}-${b}"`)

3) Emit stable link identity for every adjacency

- Each realized p2p link must carry a stable `id` (e.g. `link::<hash-or-escaped-lane>`)
- `src/solver/site/topology/transit.nix` must:
  - allow multiple p2p links with the same members
  - stop treating node-pair lookup as a unique key (pair lookup becomes ambiguous by design)

4) Make transit ordering lane-aware

- `src/solver/site/transit-ordering.nix` should accept a list of lane edges, not just node pairs.
- Canonical stage adjacency checks still apply, but per lane edge.
- If an ordering entry is a node pair, it expands to the default lane only (back-compat).

5) Derive lanes from intent (minimum viable)

Start with lane derivation driven by egress intent:

- For each access unit (or access class), compute the set of allowed uplinks from `relations -> to.kind="external"`.
- Create a distinct lane per `(access-class, uplink)` between:
  - downstream-selector <-> policy
  - policy <-> upstream-selector

Later extensions:

- Overlay lanes (must-traverse-policy overlays)
- Service-specific lanes (if required by contract model)
- Site-to-site / inter-site lanes

6) Expose lane metadata for downstream binding

Forwarding model output should include enough data for CPM/inventory binding:

- lane id/name on `transit.adjacencies[]`
- semantic tags (tenant/access class, uplink name, overlay name, etc) as plain data

### Tests (must add)

- Positive: multi-wan intent produces >1 adjacency between `policy` and `upstream-selector` with stable distinct ids.
- Determinism: lane generation is stable (same intent => same ids/order/addresses).
- Negative: if CPM/inventory cannot bind a required lane, it must fail (no guess/no collapse).
- Regression: existing single-lane sites remain unchanged (or only gain explicit default lane ids).
