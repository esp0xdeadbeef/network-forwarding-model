# network-forwarding-model Regression Notes

This file records current policy exceptions only. Keep entries exact and
current; do not use it as a session log.

## Nix File LOC States

The file-size guard requires every tracked Nix file over the soft limit to have
a current state and reason. Files at or above the hard limit fail immediately
and must be split before tests can pass.

<!-- nix-file-loc:start -->
409 s88/solver/EquipmentModule/wan.nix | state=watch | reason=WAN realization normalization still includes validation helpers
360 lib/routing/cidr-summary.nix | state=watch | reason=CIDR summarization owns shared interval ordering
350 lib/topology-resolve.nix | state=watch | reason=topology resolution owns endpoint normalization
344 s88/solver/Site/topology/transit.nix | state=watch | reason=transit derivation remains one focused pass
329 s88/solver/Site/topology/lane-links.nix | state=watch | reason=lane link derivation owns deterministic lane naming
323 lib/routing/internal-routes.nix | state=watch | reason=internal route aggregation owns site-prefix propagation
285 lib/routing/resolve-loopbacks.nix | state=watch | reason=loopback route resolution remains one focused but oversized pass
271 s88/solver/Site/topology/semantics.nix | state=watch | reason=semantic annotation owns final site annotation after role capability tables were split out
261 s88/solver/Site/topology/emitted-site.nix | state=watch | reason=emitted topology metadata owns final output shaping
261 s88/main.nix | state=watch | reason=top-level solver orchestration remains centralized
250 s88/solver/Site/topology/build.nix | state=watch | reason=topology construction now owns the high-level build sequence
242 lib/topology/resolve-helpers.nix | state=watch | reason=resolve helper collection is above soft limit but below hard limit
228 flake.nix | state=watch | reason=flake app/test wiring is above soft limit and should not grow further
213 lib/routing/static-helpers.nix | state=watch | reason=shared route helpers remain above the soft limit after CIDR summarization was split out
210 s88/solver/Unit/roles.nix | state=watch | reason=role inference and validation remain together just above soft limit
204 lib/fabric/invariants/final-topology-links.nix | state=watch | reason=final link integrity owns node-interface reverse membership checks
<!-- nix-file-loc:end -->

## Architecture Shape

- state=implemented-in-progress | target=s88/solver/{Enterprise,Site,Unit,EquipmentModule,ControlModule} layout | reason=forwarding-model code now follows the CPM-style S88 responsibility split; old solver entrypoints must remain thin imports only while oversized Site/routing modules are split further.
- state=hard-guard | target=tests/test-s88-structure-layout.sh | reason=the S88 directory split must be a real filesystem boundary, not README wording; compatibility files may import but must not keep solver policy.
- state=required | target=no oversized implementation files | reason=Nix implementation files over 200 LOC must be split by concrete responsibility unless they are flake/test wiring or explicitly documented as a temporary regression with a split target.

## S88 Keyword Boundary

- state=hard-guard | target=tests/test-s88-structure-keywords.sh | reason=Repeated role words, protocol abbreviations, lab identities, generated-name fragments, and string parsing primitives in implementation code mean the S88 structure is not the owner of the problem yet.
- state=required | target=segmented S88 modules | reason=Problem-specific files must parse names once at the boundary, then pass structured data forward; scattered access/policy/core/uplink/site/example matching is how compiled output gets half-tested and half-missed.
- state=allowed | target=include/import boundaries only | reason=Compatibility entrypoints may mention old paths while they import the owning S88 module, but they must not retain solver logic.
