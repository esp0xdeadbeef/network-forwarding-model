# network-forwarding-model Regression Notes

This file records current policy exceptions only. Keep entries exact and
current; do not use it as a session log.

## Nix File LOC States

The file-size guard requires every tracked Nix file over the soft limit to have
a current state and reason. Files at or above the hard limit fail immediately
and must be split before tests can pass.

<!-- nix-file-loc:start -->
211 lib/model/routes.nix | state=watch | reason=route normalization now owns shared route entry coercion, intent annotation, and route dedupe until route-key helpers are split
360 lib/routing/cidr-summary.nix | state=watch | reason=CIDR summarization owns shared interval ordering
350 lib/topology-resolve.nix | state=watch | reason=topology resolution owns endpoint normalization
344 s88/Site/topology/transit.nix | state=watch | reason=transit derivation owns staged adjacency expansion from canonical ordering into emitted transit metadata; split target is selector-lane expansion first
323 lib/routing/internal-routes.nix | state=watch | reason=internal route aggregation owns site-prefix propagation
285 lib/routing/resolve-loopbacks.nix | state=watch | reason=loopback route resolution remains one focused but oversized pass
261 s88/Site/topology/emitted-site.nix | state=watch | reason=emitted-site projection owns the final site attrset boundary after topology passes finish; split target is output metadata projection
261 s88/build.nix | state=watch | reason=top-level forwarding build orchestration remains centralized after the public entrypoint was renamed out of generic main/default naming
250 s88/Site/topology/build.nix | state=watch | reason=topology build owns pass ordering for pool, semantic, lane, transit, overlay, and emission modules; split target is a declarative pass list
242 lib/topology/resolve-helpers.nix | state=watch | reason=resolve helper collection is above soft limit but below hard limit
232 flake.nix | state=watch | reason=flake app/test wiring is above soft limit and should not grow further
213 lib/routing/static-helpers.nix | state=watch | reason=shared route helpers remain above the soft limit after CIDR summarization was split out
210 s88/Unit/roles/build.nix | state=watch | reason=unit role projection owns the canonical role capability table plus role selection boundary; split target is capability data extraction
204 lib/fabric/invariants/final-topology-links.nix | state=watch | reason=final link integrity owns node-interface reverse membership checks
<!-- nix-file-loc:end -->

## Architecture Shape

- state=implemented-in-progress | target=s88/{Enterprise,Site,Unit,ControlModule} plus compiler-input/sites boundary | reason=forwarding-model code now follows a responsibility split closer to S88 after checking ISA-88/S88 references: compiler input normalization is not an S88 equipment/control layer, so it lives outside s88 while the active s88 tree owns enterprise/site/unit/control-module forwarding behavior.
- state=removed | target=s88/solver | reason=solver was a fake umbrella that described an algorithm, not an S88 responsibility. The active tree must not contain a solver directory; older paths are available through git history instead of compatibility imports.
- state=removed | target=s88/site and s88/site.nix | reason=lowercase site duplicated the real Site ownership boundary and made the tree look like it had two site authorities. The old compatibility files were removed from the active tree and should be inspected through git log or git show --find-renames.
- state=removed | target=s88/default.nix and s88/main.nix | reason=generic entrypoint names hid two different meanings. The public forwarding build is now s88/build.nix; enterprise dispatch is s88/Enterprise/build.nix.
- state=removed | target=root fixtures directory | reason=fixtures belong to the tests that consume them. Passing fixtures now live under tests/fixtures so the repository root only contains source, docs, and entrypoints.
- state=removed | target=root generated JSON outputs | reason=debug output must not leave output-compiler-signed.json or output-network-forwarding-model-signed.json in the repository root. Debug runs use a temporary directory so generated evidence does not become repository structure.
- state=removed | target=temporary legacy snapshots | reason=the repository must not keep copied old structure for review. Removed and moved files are reviewable through git log, git show --find-renames, and git diff --find-renames instead of retained as extra files.
- state=hard-guard | target=tests/test-s88-structure-layout.sh | reason=the S88 directory split must be a real filesystem boundary, not README wording; lowercase compatibility files, generic s88/default.nix, and fake input layers must not remain active imports.
- state=hard-guard | target=tests/test-no-parent-relative-imports.sh | reason=imports must use the flake self.outPath boundary instead of parent-directory traversal so examples, tests, and scripts do not depend on checkout-relative accidents.
- state=required | target=no oversized implementation files | reason=Nix implementation files over 200 LOC must be split by concrete responsibility unless they are flake/test wiring or explicitly documented as a temporary regression with a split target.

## S88 Keyword Boundary

- state=hard-guard | target=tests/test-s88-structure-keywords.sh | reason=Repeated role words, protocol abbreviations, lab identities, generated-name fragments, and string parsing primitives in implementation code mean the S88 structure is not the owner of the problem yet.
- state=non-waivable | target=tests/test-s88-structure-keywords.sh | reason=regression.md must not contain per-file keyword exceptions; the guard is intended to fail until the implementation is segmented and structured data replaces scattered parsing.
- state=required | target=segmented S88 modules | reason=Problem-specific files must parse names once at the boundary, then pass structured data forward; scattered access/policy/core/uplink/site/example matching is how compiled output gets half-tested and half-missed.
- state=allowed | target=git history only | reason=old compatibility entrypoints must be inspected through git history instead of retained in the working tree; active implementation files must use the owning S88 module paths.
- state=research-note | target=S88 naming | reason=S88 is not a generic folder style. It is an equipment/control hierarchy, so new folders should represent real ownership boundaries such as Enterprise, Site, Unit, EquipmentModule, and ControlModule, or stay outside s88 when they are compiler/input plumbing.

## Review Notes

- state=reviewable-through-git | target=large structural move | reason=this commit intentionally removes or moves a lot of files. Use git log --follow, git show --find-renames, or git diff --find-renames when reviewing old paths; keeping live compatibility shims would preserve the bad structure the cleanup is trying to remove.
- state=verified | target=focused structural tests | reason=the current structural contract is covered by PASS results for test-s88-structure-layout, test-no-parent-relative-imports, and test-nix-file-loc, plus a shallow nix eval of the flake build function.
- state=verified | target=forwarding behavior smoke | reason=lane-preserving-default-route-contract passed after the entrypoint and structure moves, proving at least one real forwarding output path still reaches the model.
