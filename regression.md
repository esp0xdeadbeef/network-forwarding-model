# regression.md

## FS-310 public-ingress target lane derivation

- state=solved
- owner: network-forwarding-model
- scope: FS-310-HDS-020-SDS-010-SMS-075 public-ingress path realization
- first-bad-artifact: The 2026-07-17 `s-router-prod` audit found an explicit `wan` to `s-nebula-container` public-ingress tuple whose provider endpoint belongs to `access-vlan3`, while NFM emitted access-uplink lanes only for outbound VLAN2 and VLAN7 relations. CPM consequently had no WAN/access-vlan3 lane to select and widened the tuple over the unrelated VLAN2 and VLAN7 lanes; a live hotpatch probe stopped at the upstream selector.
- evidence: compare `forwardingOut.enterprise.esp0xdeadbeef.site.site-a.links` with `communicationContract.relations[id=allow-wan-to-s-nebula-container].publicIngressTupleAuthority` and the service provider tenant/access ownership.
- verification: `NETWORK_REPO_DIRECT_TEST_OK=1 bash tests/fs-310-hds-020-sds-010-sms-075-public-ingress-target-lane.sh`; `NETWORK_REPO_DIRECT_TEST_OK=1 bash run-all-tests.sh` passed 62/62 construction tests after the entry was closed.
- note: topology lane presence is not packet authority. NFM must derive the one target access/uplink lane from the explicit public-ingress relation; CPM remains responsible for tuple-scoped policy, routes, translation, and fail-closed realization.

## FS-350 runtime delegated-prefix derivation metadata

- state=solved
- owner: network-forwarding-model
- scope: FS-350-HDS-010-SDS-010-SMS-060 runtime delegated-prefix route planning
- first-bad-artifact: On 2026-07-17 the representative `s-router-prod` NFM output preserved complete `/run/secrets/subnet-ipv6-vlan{2,3,7}` authority records (`delegatedPrefixLength=48`, `perTenantPrefixLength=64`, `slot`, `prefixName`) but 10 emitted runtime return routes reached CPM without that derivation metadata; 9 of those 10 routes were already incomplete in NFM `forwardingOut`.
- evidence: `NETWORK_REPO_DIRECT_TEST_OK=1 bash tests/FS-350-HDS-010-SDS-010-SMS-060-runtime-delegated-route-metadata.sh`; full NFM construction suite (49 tests) rerun after the owning-layer fix.
- note: `internal-routes/route-groups.nix` emits only `sourceFile` and `prefixName`, while the route-atom and next-hop equivalence identities do not distinguish tenant/slot/prefix-length derivations. The renderer therefore cannot derive the intended per-tenant `/64` from the protected parent prefix without a host-local repair.

## FS-390 public IPv4 same-owner tenant ownership

- state=solved
- owner: network-forwarding-model
- scope: FS-390-HDS-010-SDS-010-SMS-010 public IPv4 destination ownership
- first-bad-artifact: `FS-800-HDS-010-SDS-020-SMS-040` active-lab source failed during `builtins.toJSON fm.enterprise` with `ambiguous-public-ipv4-destination-ownership: 203.0.113.0=[...provider-handoff-a:domains.tenants,...provider-handoff-a:ownership.prefixes]`.
- evidence: `NETWORK_REPO_DIRECT_TEST_OK=1 bash tests/fs-390-hds-010-sds-010-sms-010.sh`
- note: NFM derives `domains.tenants` from `site.ownership.prefixes` when explicit domains are absent, then public IPv4 ownership also consumed the same tenant prefix from `ownership.prefixes`. Same address, destination class, owner kind, and owner name are one authority fact; different owners/classes must still fail as ambiguous.

## FS-940 NFM site route-plan materializer

- state=solved
- owner: network-forwarding-model
- scope: FS-940-HDS-010-SDS-020-SMS-010 site route-plan materializer
- evidence: `NETWORK_REPO_DIRECT_TEST_OK=1 bash tests/test-internal-route-site-plan-contract.sh`, `NETWORK_REPO_DIRECT_TEST_OK=1 bash tests/test-internal-route-source-group-contract.sh`, `NETWORK_REPO_DIRECT_TEST_OK=1 bash tests/test-internal-route-coordinator-contract.sh`, `NETWORK_REPO_DIRECT_TEST_OK=1 bash tests/test-internal-route-equivalence-contract.sh`, `NETWORK_REPO_DIRECT_TEST_OK=1 bash tests/test-internal-route-profile-hypothesis.sh`, `NETWORK_REPO_DIRECT_TEST_OK=1 bash benchmarks/overlay-semantic-eval.sh`
- note: The route-plan surface now emits construction diagnostics for route atoms, source eligibility, next-hop/equivalence records, exact-only and materialized route counts, and benchmark evidence passes the 3000 ms NFM semantic budget without changing route-cardinality semantics.

## FS-525 / FS-540 named recursive DNS forwarding authority

- state=solved
- owner: network-forwarding-model
- scope: FS-525-HDS-010-SDS-010-SMS-010 and FS-540-HDS-010-SDS-010-SMS-010 through SMS-045
- first-bad-artifact: The 2026-07-18 pipeline audit found that NFM reconstructs `communicationContract` from `meta.provenance.originalInputs` instead of consuming the compiler-normalized relation and service surface. A named core DNS provider can therefore survive only as an incidental site field while its provider-node ownership and explicit requester/resolver path have no forwarding-model authority. In multi-core or multi-egress sites this leaves CPM without one reproducible modeled provider path.
- required-fix: Consume the compiler-emitted DNS contract and preserve the named provider-node, resolver path, address-family requirements, recursion/local-authority boundary, and egress selector as forwarding authority. Derive only topology consequences; do not select concrete DNS addresses or invent fallback resolvers.
- implemented-fix: `compiler-input/sites/shape.nix` now treats compiler-emitted relations and services as the authoritative communication contract, adds only the compatibility `id` and `priority` view required by NFM, and retains the compiler-owned `dns` contract unchanged. Original intent remains provenance; it is no longer a substitute for compiler normalization.
- evidence: `NETWORK_REPO_DIRECT_TEST_OK=1 NETWORK_LABS_PATH=/home/deadbeef/github/network-labs bash tests/test-FS-525-HDS-010-SDS-010-SMS-010-named-core-dns-authority.sh` proves the named core service, symmetric relation, and exact five-node path survive. Permuted ambiguous provider candidates preserve byte-equivalent warnings apart from site identity, emit sorted modeled IDs, and expose no core service authority.
