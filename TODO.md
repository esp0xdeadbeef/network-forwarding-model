<!-- TODO.md -->

# TODO — network-forwarding-model

## Current status

This change set materially improved the repo:

* public naming moved further from `solver` to `network-forwarding-model`
* `src/solver/site/topology/build.nix` was split into focused modules
* stable link identities now exist in realized topology
* transit adjacencies now carry stable IDs
* transit ordering validation is stricter
* duplicate logical p2p links / self-links are rejected earlier
* pool validation is stricter and closer to the actual model
* query helpers were cleaned up and exported more intentionally
* loopbacks now participate in duplicate-address checks
* final topology integrity is checked against realized p2p adjacency output

The remaining work is mostly about **finishing the rename**, **making the contract explicit**, **hardening the new invariants**, and **locking behavior with tests**.

## Hard reset assumptions

Backward compatibility for **inputs** is not required.
Backward compatibility for **outputs** is not required.
There is no need for migration shims, legacy field preservation, or compatibility normalization.
If the cleanest path is to remove old shapes and rebuild the repo contract from the current design, do that.

---

# 1. Finish the rename cleanly

## 1.1 Public surfaces

* [ ] Audit for remaining user-facing `solver` wording in:

  * [ ] README
  * [ ] shell scripts
  * [ ] example output paths
  * [ ] jq snippets / helper tooling
  * [ ] comments and diagnostics that still describe this stage as a “solver”
* [ ] Confirm the deleted `output-solver-signed.json` artifact is gone from all scripts and docs
* [ ] Ensure the only signed output name is `output-network-forwarding-model-signed.json`
* [ ] Check whether `compile-and-solve` app/package naming should now also be renamed

## 1.2 Internal structure naming

* [ ] Decide whether `src/solver/*` should remain as an implementation path or be renamed to something like:

  * [ ] `src/forwarding-model/*`
  * [ ] `src/build-forwarding-model/*`
  * [ ] another explicit stage name
* [ ] If internal path rename is desired, do it in one pass instead of leaving half-renamed internals
* [ ] Rename local function names that still preserve old stage vocabulary where they leak intent

---

# 2. Make the input/output contract explicit

## 2.0 No backward-compatibility work

* [ ] Do **not** preserve legacy input shapes just because older examples used them
* [ ] Do **not** preserve old output field names or artifact names for downstream consumers
* [ ] Do **not** add compatibility normalization for deprecated contracts
* [ ] Delete old shapes outright when they conflict with the intended model
* [ ] Prefer a clean contract rewrite over a mixed old/new transitional design

## 2.1 Transit ordering contract

Right now the code is between two worlds:

* input still accepts / derives **node-pair ordering**
* realized output now emits **stable link identity ordering**

That boundary must become explicit.

* [ ] Decide the canonical input contract for `site.transit.ordering`
* [ ] Decide the single canonical input contract for transit ordering
* [ ] Remove all alternative legacy shapes instead of supporting multiple forms in parallel
* [ ] Document the exact output contract:

  * [ ] `transit.ordering = [ <stable-link-id> ... ]`
  * [ ] `transit.adjacencies[].id`
  * [ ] adjacency endpoint schema
* [ ] Make sure every error message distinguishes clearly between:

  * [ ] malformed input ordering
  * [ ] ambiguous node-pair lookup
  * [ ] unknown realized link identity
  * [ ] incomplete realized ordering set

## 2.2 Derived enrichment in `src/main.nix`

`src/main.nix` now merges and derives a lot more than before.
That is useful, but the contract is getting blurry.

* [ ] Document exactly what `src/main.nix` is allowed to enrich/normalize:

  * [ ] attachments
  * [ ] communicationContract
  * [ ] transport
  * [ ] transit.ordering
  * [ ] addressPools
  * [ ] domains.tenants
* [ ] Decide whether this enrichment belongs in `src/main.nix` or should move into a dedicated normalization stage
* [ ] Ensure this stage never silently invents semantics from incidental attr ordering
* [ ] Remove derivation paths that only exist to soften old contracts

## 2.3 Schema versioning

* [ ] Document what changed from `schemaVersion = 5` to `schemaVersion = 6`
* [ ] State which fields changed shape, which were renamed, and which are new
* [ ] Treat this as a hard contract reset, not a compatibility migration

---

# 3. Follow through on the topology module split

The large `build.nix` split landed, but the refactor is not done just because the file got smaller.

## 3.1 Module boundaries

* [ ] Verify each new module has one clear responsibility:

  * [ ] `common.nix`
  * [ ] `domains.nix`
  * [ ] `overlays.nix`
  * [ ] `pools.nix`
  * [ ] `tenants.nix`
  * [ ] `transit.nix`
* [ ] Check for cross-module leakage or circular semantic dependencies
* [ ] Move anything still overly generic or misplaced into a better home

## 3.2 Naming quality

* [ ] Audit exported function names in the new topology modules for clarity and consistency
* [ ] Ensure functions that operate on raw intent vs realized topology are named differently
* [ ] Avoid helper names that are too generic for their actual contract

## 3.3 Remaining extraction opportunities

* [ ] Decide whether pool/address validation should stay under topology or move into a more explicit validation layer
* [ ] Decide whether overlay reachability derivation belongs with topology construction or route/model generation
* [ ] Decide whether transit identity conversion belongs in topology or a dedicated contract-normalization module

---

# 4. Harden the new invariants

## 4.1 Container-aware invariant scaffolding

`lib/fabric/invariants/common.nix` now discovers container contexts heuristically. That is useful, but easy to get subtly wrong.

* [ ] Test `containersOf` against all supported node/container shapes
* [ ] Test `isContainerAttr` against false positives from ordinary nested attrs
* [ ] Decide whether container discovery should remain heuristic or become schema-driven
* [ ] Ensure reserved-node-attr exclusions are complete and future-proof enough

## 4.2 Core/container interface uniqueness

* [ ] Add positive and negative tests for `core-containers-unique-interfaces.nix`
* [ ] Verify whether only `role = core` should be checked, or whether the invariant should apply more broadly
* [ ] Ensure duplicate detection behaves correctly across:

  * [ ] host node interfaces
  * [ ] container interfaces
  * [ ] multiple containers on the same node

## 4.3 Final topology integrity

This invariant got much stronger and is now much closer to what the repo actually emits.

* [ ] Add regression tests for:

  * [ ] missing link IDs
  * [ ] duplicate link IDs
  * [ ] transit adjacency missing ID
  * [ ] duplicate adjacency IDs
  * [ ] adjacency IDs not matching realized links
  * [ ] adjacency endpoint set mismatch vs link members
  * [ ] missing adjacency for realized p2p link
  * [ ] extra adjacency not backed by realized p2p link

## 4.4 Other updated invariants

* [ ] Add tests covering the new multi-network logic in `ipv6-client-prefix.nix`
* [ ] Add tests proving loopbacks are included in `no-duplicate-addrs.nix`
* [ ] Add tests proving `transit-ordering-valid.nix` enforces:

  * [ ] presence when p2p exists
  * [ ] link identity membership
  * [ ] uniqueness
  * [ ] completeness

---

# 5. Tighten topology realization correctness

## 5.1 Stable link identity semantics

* [ ] Confirm `link::${siteName}::${linkName}` is the desired long-term ID format
* [ ] Decide whether link IDs should remain human-readable or become schema-versioned / namespaced more explicitly
* [ ] Ensure IDs are stable across refactors that do not change topology semantics

## 5.2 Duplicate and illegal p2p handling

* [ ] Add direct tests for:

  * [ ] duplicate logical p2p links between the same node pair
  * [ ] p2p self-links
  * [ ] p2p links resolving to anything other than exactly 2 nodes
* [ ] Check that the failure location is early and specific enough for users

## 5.3 Transit adjacency realization

* [ ] Verify adjacency endpoints intentionally require IPv4 and only optionally carry IPv6
* [ ] Decide whether IPv6 should remain optional in adjacency endpoints long-term
* [ ] Ensure adjacency member ordering is deterministic and documented
* [ ] Add tests for ambiguous pair-to-link resolution in `transitLinkIdForPair`

---

# 6. Pool and address validation follow-up

## 6.1 Validation coverage

The pool validation work is better, but it needs tests before it can be trusted.

* [ ] Add positive and negative tests for:

  * [ ] required p2p pool missing
  * [ ] required local pool missing
  * [ ] IPv4/IPv6 family mismatch
  * [ ] invalid prefix lengths
  * [ ] p2p pool exhaustion
  * [ ] local pool exhaustion
  * [ ] p2p/local overlap
  * [ ] pool overlap with tenant prefixes
  * [ ] explicit loopback outside local pool
  * [ ] WAN endpoint address outside local pool

## 6.2 Ownership and source-of-truth questions

* [ ] Decide whether local-pool loopback allocation belongs in topology build or a lower-level allocator
* [ ] Decide whether WAN local-pool validation is the right boundary here or should be enforced earlier
* [ ] Ensure explicit loopback override rules are documented and deterministic

---

# 7. Query API and developer surfaces

## 7.1 Query exports

* [ ] Add tests for `lib/query/routes-per-node.nix`
* [ ] Add tests for `lib/query/summary.nix`
* [ ] Confirm both modules are part of the intended public debugging surface
* [ ] Remove them again if they are not meant to be stable query APIs

## 7.2 Purity and consistency

* [ ] Audit all query modules for accidental impurity / hidden `<nixpkgs>` imports
* [ ] Make argument style consistent across query modules (`{ lib, topo }`, etc.)
* [ ] Document expected input shape for each query helper

---

# 8. Example and fixture coverage

## 8.1 Positive fixtures

* [ ] Minimal single-site topology with one p2p chain and one WAN uplink
* [ ] Dual-stack site with valid stable transit identities
* [ ] Site with explicit loopbacks overriding local-pool allocation
* [ ] Site with overlay reachability and resolved peer-site prefixes
* [ ] Site using attachment-derived tenant networks
* [ ] Site with container-aware core interface uniqueness passing correctly

## 8.2 Negative fixtures

* [ ] Missing `transit.ordering`
* [ ] Malformed node-pair ordering entry
* [ ] Duplicate node-pair ordering entry
* [ ] Ambiguous pair-to-link resolution
* [ ] Duplicate logical p2p link
* [ ] P2P self-link
* [ ] Missing stable link ID
* [ ] Transit adjacency ID mismatch
* [ ] Duplicate addresses via loopback collision
* [ ] Duplicate interfaces across core/container execution contexts
* [ ] Pool overlap / exhaustion cases

## 8.3 Byte-stability / determinism tests

* [ ] Same input must produce byte-stable sorted JSON across repeated runs
* [ ] Stable link IDs must remain stable across repeated runs
* [ ] Realized transit ordering must remain stable across repeated runs
* [ ] Loopback allocation must remain stable across repeated runs
* [ ] P2P allocation must remain stable across repeated runs

---

# 9. Documentation cleanup

## 9.1 README

* [ ] Rewrite the README around the current stage responsibilities:

  * [ ] compiler IR in
  * [ ] forwarding model out
  * [ ] realized topology / routes / transit identities
* [ ] Document the new topology module layout
* [ ] Document how transit ordering moves from input shape to realized stable IDs
* [ ] Document pool expectations and loopback allocation behavior
* [ ] Document invariant intent, not just invariant filenames

## 9.2 Developer notes

* [ ] Add a short architecture note explaining why `build.nix` was split and what belongs where now
* [ ] Remove references to downstream consumers of `output-solver-signed.json` instead of documenting migration
* [ ] Add a short debugging guide for common failures:

  * [ ] ambiguous transit ordering
  * [ ] duplicate logical p2p link
  * [ ] pool exhaustion
  * [ ] topology/adjacency mismatch

---

# 10. Suggested implementation order

* [ ] lock the transit input/output contract in writing
* [ ] add regression tests for stable link IDs and transit ordering
* [ ] test the strengthened invariants
* [ ] finish rename cleanup across public surfaces
* [ ] decide whether `src/solver/*` gets renamed internally
* [ ] clean up README / migration notes

---

# Done when

* [ ] there is no meaningful remaining public `solver` naming
* [ ] the transit contract is explicit instead of half-legacy / half-canonical
* [ ] topology module boundaries are understandable and defensible
* [ ] new invariants are covered by targeted positive/negative tests
* [ ] stable link identity behavior is locked by regression coverage
* [ ] downstream consumers can treat this output as the deterministic forwarding-model truth

