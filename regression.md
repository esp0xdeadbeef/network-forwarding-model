# regression.md

## FS-940 NFM site route-plan materializer

- state=solved
- owner: network-forwarding-model
- scope: FS-940-HDS-010-SDS-020-SMS-010 site route-plan materializer
- evidence: `NETWORK_REPO_DIRECT_TEST_OK=1 bash tests/test-internal-route-site-plan-contract.sh`, `NETWORK_REPO_DIRECT_TEST_OK=1 bash tests/test-internal-route-source-group-contract.sh`, `NETWORK_REPO_DIRECT_TEST_OK=1 bash tests/test-internal-route-coordinator-contract.sh`, `NETWORK_REPO_DIRECT_TEST_OK=1 bash tests/test-internal-route-equivalence-contract.sh`, `NETWORK_REPO_DIRECT_TEST_OK=1 bash tests/test-internal-route-profile-hypothesis.sh`, `NETWORK_REPO_DIRECT_TEST_OK=1 bash benchmarks/overlay-semantic-eval.sh`
- note: The route-plan surface now emits construction diagnostics for route atoms, source eligibility, next-hop/equivalence records, exact-only and materialized route counts, and benchmark evidence passes the 3000 ms NFM semantic budget without changing route-cardinality semantics.
