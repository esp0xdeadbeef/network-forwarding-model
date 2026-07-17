# regression.md

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
