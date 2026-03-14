TODO — Solver: Canonicalize forwarding routes

Problem
Multiple solver stages may emit routes describing the same
forwarding relationship (same dst and via).

This results in duplicate route objects such as:

    proto=uplink  dst=0.0.0.0/0 via=X
    proto=default dst=0.0.0.0/0 via=X

These represent identical forwarding behavior.

Required behavior
The solved operational model must contain a single canonical
route per (dst, via) pair.

Invariant
For every interface routing table:

    unique (dst, via) pairs

Fix
Introduce route canonicalization during route synthesis:

1. Collect all candidate routes.
2. Deduplicate by (dst, via).
3. Preserve semantic proto where meaningful.
4. Emit a single route object.

Validation
Solver output must not contain multiple routes with the
same destination and next-hop.
