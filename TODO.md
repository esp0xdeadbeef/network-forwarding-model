# TODO

---

# Renderer

The renderer is a **pure projection layer**.

It must translate the solved network graph into runtime configuration
(Containerlab, devices, etc.) without interpreting topology or routing
semantics.

## Projection Safety

- [ ] Fail hard if any solver link is not rendered (projection must be total).
- [ ] Error if rendered topology produces zero runtime links.
- [ ] Validate rendered output against solver graph (no dropped nodes, links, or interfaces).
- [ ] Preserve solver-provided identities exactly (no renaming or topology mutation).

## Rendering Correctness

- [ ] Ensure p2p links are rendered symmetrically across endpoints.
- [ ] Maintain deterministic interface ordering and mapping.
- [ ] Emit deterministic bridge/interface naming derived only from solved inputs.

## Renderer Architecture (Future)

- [ ] Support solver-defined attachment semantics during projection.
- [ ] Introduce clear Network IR → Device IR boundary.
- [ ] Add routing-context abstraction (VRF / network-instance independent).
- [ ] Keep renderer independent of compiler internals and debug metadata.

---

# Solver Responsibilities

Goal: the solver emits a **fully decided canonical network graph** so that
renderers require no semantic interpretation.

Solver output represents network truth.

## Topology Ownership

- [ ] Emit final node identities and names.
- [ ] Resolve enforcement ownership during solving.
- [ ] Ensure all link endpoints reference existing nodes.
- [ ] Create WAN/ISP peer nodes explicitly in solver output.
- [ ] Ensure topology is complete before emission.

## Self-Contained Output

- [ ] Resolve compiler IR attachments during solving.
- [ ] Do not require `_debug` or compiler metadata downstream.
- [ ] Solver JSON must be self-contained and renderer-ready.

## Routing Truth

- [ ] Emit complete routing intent explicitly.
- [ ] Decide and enforce connected-route model (explicit or implicit).
- [ ] Remove need for renderer-side routing assumptions.

## Link Semantics

- [ ] Emit fully solved link types (`p2p`, `lan`, etc.).
- [ ] Define link behavior entirely within solver output.

## Validation

- [ ] Fail solver on dangling links.
- [ ] Fail solver on incomplete node or interface definitions.
- [ ] Validate topology and routing consistency before output.

## Contract

Solver output is a canonical graph:

- topology immutable downstream
- identities final
- routing complete
- no semantic interpretation required by renderer
