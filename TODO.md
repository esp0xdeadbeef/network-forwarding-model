# TODO

## Forwarding-model: fixed / no further action

- Keep canonical forwarding authority under:
  - `site.links`
  - `site.transit`
  - `site.attachments`
  - `site.domains`
  - `tenantPrefixOwners`
  - `loopbacks`
  - node interfaces
- Do not emit solved-site `transport` as canonical output authority.
- Do not emit legacy tenant-interface `link` on logical tenant interfaces.
- Do not synthesize null-address WAN forwarding interfaces in solved node interface maps.

## Forwarding-model: remaining work actually owned here

- Make forwarding semantics explicit without relying on role-only interpretation:
  - add explicit per-node forwarding function markers
  - add explicit per-node traversal participation markers
  - add explicit per-node routing authority / forwarding responsibility markers
- Make route semantic intent explicit in solved output:
  - stop leaving intent inferable only from `proto`
  - add explicit route intent fields for:
    - connected reachability
    - internal reachability
    - overlay reachability
    - uplink-learned reachability
    - default reachability
- Make egress intent explicit in solved output:
  - add explicit egress authority markers
  - add explicit upstream-selection / exit eligibility markers
  - do not require downstream consumers to infer egress from externals, WAN presence, or route shape

## Control-plane-model: owned there, not forwarding-model

- Derive `wanInterfaces` from CPM runtime/interface realization, not from forwarding-model solved node interfaces.
- Decide whether empty `transit.ordering = []` means:
  - canonical empty adjacency-id ordering
  - or legacy solver-era pair ordering
- Suppress the pair-ordering migration warning when the value is canonically empty and there are no realized transit adjacencies.
- Consume explicit forwarding semantics once forwarding-model emits them.
- Consume explicit route intent once forwarding-model emits it.
- Consume explicit egress intent once forwarding-model emits it.

## Boundary notes

- Forwarding-model owns solved forwarding structure and explicit intent.
- Control-plane-model owns runtime interface realization and downstream interface-derived views.
- `wanInterfaces` is CPM runtime materialization, not forwarding-model canonical interface authority.
