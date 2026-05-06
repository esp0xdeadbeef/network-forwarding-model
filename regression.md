# network-forwarding-model Regression Notes

This file records current structural policy and hard guards. Do not use it as a
session log, and do not use it to waive implementation problems that should be
fixed by layering.

## Architecture Shape

- state=implemented-in-progress | target=s88/{Enterprise,Site,Unit,ControlModule} plus compiler-input/sites boundary | reason=forwarding-model code now follows a responsibility split closer to S88 after checking ISA-88/S88 references: compiler input normalization is not an S88 equipment/control layer, so it lives outside s88 while the active s88 tree owns enterprise/site/unit/control-module forwarding behavior.
- state=required | target=public s88 and lib files | reason=public module paths are import boundaries that load implementation through self.outPath. This keeps flake-visible paths stable while preventing parent-directory traversal and checkout-relative imports.
- state=required | target=implementation/s88 | reason=active S88 implementation lives in responsibility-named modules under Enterprise, Site, Unit, and ControlModule. Shared or generic code must not be hidden inside s88 just because an S88 module calls it.
- state=required | target=lib/s88-support and implementation/lib/s88-support | reason=S88 attachment helpers are shared support library code, not S88 equipment hierarchy. Keeping them outside s88 prevents util-style folders from becoming a second ownership layer.
- state=removed | target=s88/solver | reason=solver was a fake umbrella that described an algorithm, not an S88 responsibility. The active tree must not contain a solver directory; older paths are available through git history instead of compatibility imports.
- state=removed | target=s88/site and s88/site.nix | reason=lowercase site duplicated the real Site ownership boundary and made the tree look like it had two site authorities. The old compatibility files were removed from the active tree and should be inspected through git log or git show --find-renames.
- state=removed | target=s88/default.nix and s88/main.nix | reason=generic entrypoint names hid two different meanings. The public forwarding build is now s88/build.nix; enterprise dispatch is s88/Enterprise/build.nix.
- state=removed | target=s88/util | reason=util is not an S88 ownership boundary. Any reusable helper must live in lib with a concrete name and be passed only the data needed by the caller.
- state=removed | target=root fixtures directory | reason=fixtures belong to the tests that consume them. Passing fixtures now live under tests/fixtures so the repository root only contains source, docs, and entrypoints.
- state=removed | target=root generated JSON outputs | reason=debug output must not leave output-compiler-signed.json or output-network-forwarding-model-signed.json in the repository root. Debug runs use a temporary directory so generated evidence does not become repository structure.
- state=removed | target=temporary legacy snapshots | reason=the repository must not keep copied old structure for review. Removed and moved files are reviewable through git log, git show --find-renames, and git diff --find-renames instead of retained as extra files.
- state=hard-guard | target=tests/test-s88-structure-layout.sh | reason=the S88 directory split must be a real filesystem boundary, not README wording; lowercase compatibility files, generic s88/default.nix, and fake input layers must not remain active imports.
- state=hard-guard | target=tests/test-no-parent-relative-imports.sh | reason=imports must use the flake self.outPath boundary instead of parent-directory traversal so examples, tests, and scripts do not depend on checkout-relative accidents.

## Layering Policy

- state=required | target=all implementation files | reason=correct layering is required; oversized files are not tracked as regression exceptions because size notes become an excuse to keep bad boundaries.
- state=allowed | target=flake.lock | reason=flake.lock is generated lock state and is the only file allowed to be large by context rather than by implementation ownership.
- state=non-waivable | target=tests/test-s88-structure-keywords.sh | reason=regression.md must not contain per-file keyword exceptions; the guard is intended to fail until the implementation is segmented and structured data replaces scattered parsing.
- state=hard-guard | target=tests/test-nix-file-loc.sh | reason=large Nix implementation files must be split into concrete responsibilities. flake.nix is excluded from this guard because flake wiring is context-heavy and not a useful place to force artificial layering.
- state=required | target=p2p and transit derivation | reason=point-to-point link parsing is general topology behavior. Role-specific modules may contribute requirements, but generic node-to-node link materialization belongs in shared topology passes.
- state=required | target=service-specific behavior | reason=services such as DHCP must be represented by named service modules instead of scattered string checks across role files.

## S88 Keyword Boundary

- state=hard-guard | target=tests/test-s88-structure-keywords.sh | reason=Repeated role words, protocol abbreviations, lab identities, generated-name fragments, and string parsing primitives in implementation code mean the S88 structure is not the owner of the problem yet.
- state=required | target=segmented S88 modules | reason=Problem-specific files must parse names once at the boundary, then pass structured data forward; scattered access/policy/core/uplink/site/example matching is how compiled output gets half-tested and half-missed.
- state=allowed | target=git history only | reason=old compatibility entrypoints must be inspected through git history instead of retained in the working tree; active implementation files must use the owning S88 module paths.
- state=research-note | target=S88 naming | reason=S88 is not a generic folder style. It is an equipment/control hierarchy, so new folders should represent real ownership boundaries such as Enterprise, Site, Unit, EquipmentModule, and ControlModule, or stay outside s88 when they are compiler/input plumbing.

## Review Notes

- state=reviewable-through-git | target=large structural move | reason=this commit intentionally removes or moves a lot of files. Use git log --follow, git show --find-renames, or git diff --find-renames when reviewing old paths; keeping live compatibility shims would preserve the bad structure the cleanup is trying to remove.
- state=verified | target=focused structural tests | reason=the current structural contract is covered by PASS results for test-s88-structure-layout, test-s88-structure-keywords, test-no-parent-relative-imports, and test-nix-file-loc, plus a shallow nix eval of the flake build function.
- state=verified | target=forwarding behavior smoke | reason=lane-preserving-default-route-contract passed after the entrypoint and structure moves, proving at least one real forwarding output path still reaches the model.
