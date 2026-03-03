# TODO

# Renderer

Pure projection layer.

- [ ] Render all solver nodes, links, and interfaces.
- [ ] Fail if any solver element is not projected.
- [ ] Preserve identities exactly (no renaming, no mutation).
- [ ] Do not invent topology, routes, or aggregation.
- [ ] Emit only routes explicitly provided by solver.
- [ ] Render links symmetrically and deterministically.


# Solver

Emits canonical, fully decided network graph.

- [ ] Emit complete topology (nodes, links, interfaces).
- [ ] Ensure all links reference valid nodes.
- [ ] Emit explicit link types and interface bindings.
- [ ] Emit complete routing state (no inference required).
- [ ] Decide and emit aggregation policy.
- [ ] Fail on dangling links or inconsistent routing.

Solver output is authoritative and immutable downstream.
Renderer performs zero semantic interpretation.
