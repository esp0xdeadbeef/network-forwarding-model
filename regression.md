# network-forwarding-model Regression Notes

This file records current policy exceptions only. Keep entries exact and
current; do not use it as a session log.

## Nix File LOC States

The file-size guard requires every tracked Nix file over the soft limit to have
a current state and reason. Files at or above the hard limit fail immediately
and must be split before tests can pass.

<!-- nix-file-loc:start -->
409 src/solver/site/wan.nix | state=watch | reason=WAN realization normalization still includes validation helpers
360 lib/routing/cidr-summary.nix | state=watch | reason=CIDR summarization owns shared interval ordering
350 lib/topology-resolve.nix | state=watch | reason=topology resolution owns endpoint normalization
344 src/solver/site/topology/transit.nix | state=watch | reason=transit derivation remains one focused pass
329 src/solver/site/topology/lane-links.nix | state=watch | reason=lane link derivation owns deterministic lane naming
323 lib/routing/internal-routes.nix | state=watch | reason=internal route aggregation owns site-prefix propagation
285 lib/routing/resolve-loopbacks.nix | state=watch | reason=loopback route resolution remains one focused but oversized pass
271 src/solver/site/topology/semantics.nix | state=watch | reason=semantic annotation owns final site annotation after role capability tables were split out
261 src/solver/site/topology/emitted-site.nix | state=watch | reason=emitted topology metadata owns final output shaping
261 src/main.nix | state=watch | reason=top-level solver orchestration remains centralized
250 src/solver/site/topology/build.nix | state=watch | reason=topology construction now owns the high-level build sequence
242 lib/topology/resolve-helpers.nix | state=watch | reason=resolve helper collection is above soft limit but below hard limit
228 flake.nix | state=watch | reason=flake app/test wiring is above soft limit and should not grow further
213 lib/routing/static-helpers.nix | state=watch | reason=shared route helpers remain above the soft limit after CIDR summarization was split out
210 src/solver/site/roles.nix | state=watch | reason=role inference and validation remain together just above soft limit
204 lib/fabric/invariants/final-topology-links.nix | state=watch | reason=final link integrity owns node-interface reverse membership checks
<!-- nix-file-loc:end -->

## Architecture Shape

- state=required | target=s88-style Enterprise/Site/Unit/EquipmentModule/ControlModule layout | reason=forwarding-model code must be organized by model responsibility, with top-level files limited to flakes, tests, entrypoints, and thin imports into s88-style responsibility folders; solver policy must not be added as root-level blobs.
- state=required | target=no oversized implementation files | reason=Nix implementation files over 200 LOC must be split by concrete responsibility unless they are flake/test wiring or explicitly documented as a temporary regression with a split target.

## S88 Keyword Boundary

Stage terms such as access, policy, downstream-selector, upstream-selector,
core, and common abbreviations are allowed in the role/stage ownership modules.
Other implementation files must not grow new stage-name logic unless the
exception below explains the concrete structural reason. Documented exceptions
warn with their exception context; undocumented matches hard-fail and must be
fixed by implementing the S88 structure or adding a real regression reason.

<!-- s88-keyword-boundary:start -->
src/main.nix | state=warn | reason=top-level orchestration still emits the overlay access-lane diagnostic and output metadata while warning plumbing is not split into a dedicated S88 validation module
src/normalize-sites.nix | state=warn | reason=normalization still bridges legacy compiler fields such as coreNodeNames and policyNodeName into the staged site shape before role ownership modules consume them
src/normalize-sites/default-site.nix | state=warn | reason=default site construction must preserve empty policy and core metadata fields for old canonical inputs until normalization compatibility is removed
src/normalize-sites/domains.nix | state=warn | reason=domain normalization still consumes legacy site.policy.interfaceTags while converting older input shape into explicit domain data
src/normalize-sites/site-shape.nix | state=warn | reason=site-shape compatibility detects legacy core hints while translating old inputs into the canonical staged site envelope
src/solver/site.nix | state=warn | reason=site-level build still passes role and topology results between S88 ownership modules and should eventually become a thinner import-only coordinator
src/solver/site/enforcement.nix | state=warn | reason=enforcement normalization still strips legacy policy interfaceTags from old inputs before the dedicated domain and role modules own the resulting structure
src/solver/site/topology/build.nix | state=warn | reason=topology build still joins role-derived core and policy metadata into the emitted site and should be split once topology orchestration is reduced further
src/solver/site/topology/emitted-site.nix | state=warn | reason=emitted-site materialization still copies policy and core role metadata into final output because downstream CPM currently consumes those explicit fields
src/solver/site/topology/overlay-reachability.nix | state=warn | reason=overlay reachability still checks core-owned termination paths while deriving overlay routes and should move core selection into a narrower overlay ownership helper
src/solver/site/topology/transit.nix | state=warn | reason=transit derivation still validates stage-ordered adjacency and route ownership in one pass because staged topology output depends on both checks
src/solver/site/transit-ordering.nix | state=warn | reason=transit ordering compatibility still normalizes role-ordered edge hints before the dedicated transit topology modules consume the canonical adjacency list
src/solver/site/wan.nix | state=warn | reason=WAN realization still filters core uplink ownership and validates endpoint completeness before emitting forwarding-only WAN links
lib/fabric/invariants/core-containers-unique-interfaces.nix | state=warn | reason=legacy invariant name contains core and still checks final interface uniqueness while container placement leakage is being removed from forwarding output
lib/fabric/invariants/core-no-duplicate-interface-names.nix | state=warn | reason=legacy invariant name contains core and still guards final interface uniqueness until role-neutral interface invariant names replace it
lib/fabric/invariants/final-topology-links.nix | state=warn | reason=final link integrity checks role-derived lane metadata on emitted topology links and has not yet been split from generic endpoint integrity
lib/fabric/invariants/final-topology-transit.nix | state=warn | reason=final transit integrity still validates stage-derived transit metadata on emitted links instead of delegating all stage checks to transit-role modules
lib/fabric/invariants/ipv6-client-prefix.nix | state=warn | reason=IPv6 client-prefix validation is intentionally scoped to access-owned tenant networks and should remain isolated to this invariant
lib/fabric/invariants/node-role-interface-degree.nix | state=warn | reason=interface-degree validation has one access-specific structural requirement and should move under node-role invariants when that folder is normalized
lib/fabric/invariants/overlay-core-uplink-dedicated.nix | state=warn | reason=overlay termination has a real core-specific invariant requiring dedicated overlay uplinks, but the invariant should remain isolated here
lib/query/multi-wan.nix | state=warn | reason=query helper exposes upstream selector to uplink-core adjacency for debugging multi-WAN output and must stay read-only rather than become solver logic
lib/query/node-context.nix | state=warn | reason=query helper maps core-derived fabric host context for debug views and must stay read-only rather than feed forwarding decisions
lib/routing/default-routes.nix | state=warn | reason=default route construction still carries preferred access and uplink lane metadata so downstream stages can preserve S88 traversal without parsing link names
lib/routing/external-ingress-uplink-defaults.nix | state=warn | reason=external ingress defaults still need core uplink ownership and policy lane metadata to keep ingress routes tied to explicit forwarding authority
lib/routing/internal-routes.nix | state=warn | reason=internal route propagation still carries access and uplink lane ownership through route intent until lane-aware routing is split by responsibility
lib/routing/lane-default-route-builder.nix | state=warn | reason=lane default route building is explicitly about access-lane and uplink-lane default reachability and should remain the only route builder with those terms
lib/routing/lane-defaults.nix | state=warn | reason=lane defaults still apply access-lane route metadata before the route builder split is complete
lib/routing/lane-metadata.nix | state=warn | reason=lane metadata parses existing access and uplink lane strings until lane identity becomes structured data everywhere
lib/routing/overlay-core-selection.nix | state=warn | reason=overlay route export needs core-selection semantics to avoid using overlay-only cores for non-overlay reachability
lib/routing/resolve-loopbacks.nix | state=warn | reason=loopback route resolution still uses core and policy role metadata to derive reachable control endpoints until route context ownership is split
lib/routing/route-context.nix | state=warn | reason=route context still carries preferred access and uplink lane fields so route builders can preserve staged traversal in emitted route intent
lib/routing/static-helpers.nix | state=warn | reason=shared route helpers still expose uplink core lookup and lane helpers used by several route builders before those helpers are moved into S88-scoped modules
lib/routing/static.nix | state=warn | reason=static route aggregation still sequences lane defaults, direct WAN defaults, internal routes, and uplink-learned routes through one coordinator
lib/routing/tenant-prefix-owners.nix | state=warn | reason=tenant prefix ownership still identifies access attachment owners because tenant prefixes must remain tied to their S88 ingress unit
lib/routing/uplink-learned-routes.nix | state=warn | reason=uplink-learned route export still needs core and access lane metadata to keep learned reachability on the correct staged path
lib/topology-resolve.nix | state=warn | reason=topology resolution still realizes role-derived interface and link metadata after p2p allocation and should be split into generic resolve plus S88 annotation passes
lib/topology/resolve-helpers.nix | state=warn | reason=resolve helpers still normalize role-derived route and endpoint metadata used by topology resolution before a narrower S88 helper split exists
<!-- s88-keyword-boundary:end -->
