# TODO — Solver Output Requirements

The solver must emit complete routing intent.
The renderer must only translate solver output into system commands.

Currently the solver emits only:

- connected routes
- default routes

This is insufficient for multi-hop topologies.


# Required Additions

The solver must also emit internal routing information.

Required route types:

- connected
- internal
- default
- uplink


# 1. Internal Prefix Propagation

The solver must compute reachability for prefixes that exist behind other nodes.

Example topology:

access → policy → upstream-selector → core

Example required route:

node: upstream-selector
dst: 10.10.0.0/31
via: 10.10.0.4
proto: internal

Without this, upstream nodes cannot reach downstream nodes.


# 2. Downstream Route Emission

Nodes must receive routes for networks located behind downstream nodes.

Example:

upstream-selector
→ 10.10.0.0/31 via policy


# 3. Aggregated Internal Prefixes

The solver should optionally emit aggregated prefixes.

Example aggregation:

10.10.0.0/31
10.10.0.2/31
10.10.0.4/31

aggregated into:

10.10.0.0/16

Controlled by:

aggregation.mode

Supported modes:

none
site
enterprise


# 4. Next-Hop Resolution

For every propagated prefix the solver must compute:

- next-hop IP
- outgoing interface

Algorithm:

BFS shortest path

(This algorithm is already declared in _loopbackResolution.algorithm.)


# 5. Route Emission Format

Interfaces must include routes like:

dst: 10.10.0.0/16
via4: 10.10.0.4
proto: internal

Each interface should emit a route set containing:

- connected
- internal
- default


# Success Condition

Solver output must contain all routes required for forwarding, so that:

- the renderer does not compute routes
- the renderer only converts routes into ip route commands

The generated topology must work without manual route additions.
