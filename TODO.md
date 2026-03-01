# TODO — Renderer

## Projection Safety

- [ ] Fail hard if renderer skips a link (projection must be total)
- [ ] Error if rendered topology produces zero runtime links
- [ ] Validate renderer output against solver graph (no dropped nodes/interfaces)

## Naming & Layout

- [ ] Render Access and Core using distinct naming domains
- [ ] Ensure p2p links are rendered symmetrically across endpoints

## Future Renderer Architecture

- [ ] Introduce attachment semantics (packet lifecycle stage mapping)
- [ ] Add routing-context abstraction (VRF / network-instance independent)
- [ ] Separate Network IR vs Device IR boundary
