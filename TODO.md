# Solver

Emits canonical, fully decided network graph.

- [ ] Emit complete topology (nodes, links, interfaces).
- [ ] Ensure all links reference valid nodes.
- [ ] Emit explicit link types and interface bindings.
- [ ] Emit complete routing state (no inference required).
- [ ] Decide and emit aggregation policy.
- [ ] Fail on dangling links or inconsistent routing.
- [ ] Enforce tenant prefix uniqueness across sites within the same enterprise.

- [ ] Validate external references
      Ensure every policy or NAT reference to `external` matches a declared uplink name.
      Fail compilation if a rule references a non-existent uplink.

- [ ] Fix multi-WAN detection
      Compute multi-WAN state directly from the number of uplink cores.
      multiWan = number_of_uplink_cores > 1
      query.multiWan.count must equal the number of uplink cores.
      Populate query.multiWan.links with links from selector → uplink cores.

- [ ] Support multiple core nodes
      The solver currently emits a single `coreNodeName`, but the topology now has multiple cores.
      Replace this with a structure that supports multiple cores (e.g., `coreNodeNames`).

- [ ] Derive NAT owner from uplink
      NAT ownership should correspond to the core node that hosts the uplink referenced by `fromExternal`.
      Example: if NAT ingress uses `wan`, the NAT owner should be the WAN core.

- [ ] Emit explicit default routes
      Default routes should be produced by the solver instead of inferred by the compiler.
      Nodes that should reach external networks must have explicit default routes toward the appropriate uplink path.

- [ ] Remove redundant routing structures
      Routing data is duplicated in `_bgp`, `_routingMaps`, and `query.nodes.*.routing`.
      Choose one canonical representation and remove the others.

- [ ] Generate BGP neighbors per node
      Each node get's its own `AS<ID>` and p2p via the topolinks.
      Neighbors should be derived from actual topology links.
      Each node should only list peers it is directly connected to.

- [ ] Fix invalid IPv4 prefix lengths
      The solver currently emits invalid IPv4 prefixes (e.g., `/64`).
      IPv4 prefix lengths must be ≤ 32.

- [ ] Treat uplinks as routing primitives
      Uplinks should drive routing behavior including:
      - default route injection
      - NAT ownership
      - external policy references
      - traffic steering

- [ ] Add a validation phase
      Add a final solver validation pass before emitting IR to check:
      - external references match uplinks
      - topology references valid nodes
      - routing prefixes are valid
      - no unreachable nodes exist

Solver output is authoritative and immutable downstream.
Renderer performs zero semantic interpretation.
