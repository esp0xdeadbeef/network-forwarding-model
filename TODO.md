## Landmarks
- Treat routerLoopbacks as immutable identities
- Validate loopbacks ∈ addressPools.local

## Topology
- Deterministic p2p allocation
- Emit explicit adjacency graph
- Validate transit ordering

## Forwarding Domains
- Introduce forwardingDomains abstraction
- Derive isolation + allowed edges from communicationContract

## Policy
- Normalize allowedRelations into resolved policy graph
- Detect conflicts and ambiguity

## NAT
- Resolve ingress NAT placement
- Emit explicit NAT flow definitions

## Routing Intent
- Compute prefix ownership & propagation graph
- Detect asymmetric paths during solve

## Multi-Enterprise
- Enforce namespace isolation
- Prevent unintended prefix overlap

## Debug
- Add explain/debug output mode
