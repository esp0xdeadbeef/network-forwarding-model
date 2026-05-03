# network-forwarding-model Regression Notes

This file records current policy exceptions only. Keep entries exact and
current; do not use it as a session log.

## Nix File LOC States

The file-size guard requires every tracked Nix file over the soft limit to have
a current state and reason. Files at or above the hard limit fail immediately
and must be split before tests can pass.

<!-- nix-file-loc:start -->
364 lib/routing/static.nix | state=watch | reason=static route assembly owns the ordered attachment pipeline
360 src/normalize-sites.nix | state=watch | reason=site normalization owns shape compatibility defaults
360 lib/routing/cidr-summary.nix | state=watch | reason=CIDR summarization owns shared interval ordering
350 src/solver/site/wan.nix | state=watch | reason=WAN realization normalization still includes validation helpers
350 lib/topology-resolve.nix | state=watch | reason=topology resolution owns endpoint normalization
344 src/solver/site/topology/transit.nix | state=watch | reason=transit derivation remains one focused pass
329 src/solver/site/topology/lane-links.nix | state=watch | reason=lane link derivation owns deterministic lane naming
323 lib/routing/internal-routes.nix | state=watch | reason=internal route aggregation owns site-prefix propagation
285 lib/routing/resolve-loopbacks.nix | state=watch | reason=loopback route resolution remains one focused but oversized pass
271 src/solver/site/topology/semantics.nix | state=watch | reason=semantic annotation owns final site annotation after role capability tables were split out
261 src/solver/site/topology/emitted-site.nix | state=watch | reason=emitted topology metadata owns final output shaping
261 src/main.nix | state=watch | reason=top-level solver orchestration remains centralized
257 lib/fabric/invariants/transit-ordering-valid.nix | state=watch | reason=transit ordering invariant is long and should split into smaller checks
250 src/solver/site/topology/build.nix | state=watch | reason=topology construction now owns the high-level build sequence
247 lib/routing/default-routes.nix | state=watch | reason=default route attachment owns ordered default insertion
242 lib/topology/resolve-helpers.nix | state=watch | reason=resolve helper collection is above soft limit but below hard limit
228 flake.nix | state=watch | reason=flake app/test wiring is above soft limit and should not grow further
213 lib/routing/static-helpers.nix | state=watch | reason=shared route helpers remain above the soft limit after CIDR summarization was split out
210 src/solver/site/roles.nix | state=watch | reason=role inference and validation remain together just above soft limit
204 lib/fabric/invariants/final-topology-links.nix | state=watch | reason=final link integrity owns node-interface reverse membership checks
<!-- nix-file-loc:end -->
