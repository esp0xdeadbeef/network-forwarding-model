# TODO

* Attach loopbacks directly to nodes
  Move `routerLoopbacks` into `nodes.<node>.loopback` so loopbacks become a first-class node property and the renderer does not need external lookup.

* Align policy naming
  Standardize on `policyIntent` (update documentation accordingly) to avoid mismatch with the README.

* Move query helpers to tooling
  Keep the solver output as a pure topology graph. If inspection helpers are needed, place them under `tools/query/`.

* Keep solver output free of compiler artifacts
  Ensure no compiler-stage metadata leaks into the solver graph (e.g. `compilerIR`, algorithm hints).

