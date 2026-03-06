# Solver TODO

## Correctness

* Replace `tenant = null` with explicit `"unclassified"` for uplinks without `ingressSubject`.
* Add final solver invariant validation (links reference valid nodes, interfaces exist, no orphan links).
* Fail loudly on topology resolution errors instead of silently ignoring invalid nodes.

## Architecture

* Use `build-wan-interface.nix` from `site/wan.nix` instead of duplicating WAN interface construction.
* Ensure deterministic uplink selection when multiple uplinks are present.

## IR Cleanup

* Ensure routing is canonical under `nodes.<node>.interfaces.<iface>.routes`.
* Avoid duplicating routing state (`routingTable`, `query.nodes`).

## Cleanup

* Remove legacy or unused solver helpers if present.
* Keep solver output minimal and renderer-focused (strip unused intermediate fields).

