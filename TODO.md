[ ] Realize NAT semantics: resolve communicationContract.nat into explicit core NAT ownership and mode ("none" | "custom").

[ ] Materialize multi-WAN behavior: allocate per-upstream local/LL addresses and bind WAN interfaces deterministically.

[ ] Project communication contracts into enforcement: compile allowedRelations into policy-node enforcement rules.

[ ] Convert transit ordering into enforced traversal semantics (mustTraverse / forwarding stages).

[ ] Realize overlays: instantiate overlay endpoints, tunnel bindings, and route injection instead of metadata-only definitions.

[ ] Operationalize unit isolation: map isolated containers to explicit VRFs / routing domains.

[ ] Preserve provenance: include solver git revision and input/compiler metadata in output meta section.

[ ] Emit invariant verification results (topology validity, NAT placement, traversal guarantees).

[ ] On solver failure, dump full input IR for deterministic debugging and reproduction.
