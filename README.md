# network-forwarding-model

A deterministic model builder that converts compiled network intent into a **platform-independent forwarding model**.

The forwarding model does **not** generate vendor or device configuration.
Instead, it produces a stable intermediate representation that later stages can use to derive control-plane behavior and render platform-specific outputs.

This project is intentionally **opinionated**.
It does not try to preserve arbitrary user topology as an unconstrained graph.
Instead, it takes the compiler’s canonical staged architecture and turns it into a deterministic forwarding structure with explicit authority boundaries.

Canonical traversal order:

```text
access → downstream-selector → policy → upstream-selector → core
```

That staged architecture is part of the model.
It is not incidental.

Smaller deployments may **co-locate multiple stages on the same realized node**, but the canonical model and traversal order remain the same.

---

# Disclaimer

This project exists primarily to support my own infrastructure.

If it happens to be useful to others, great — but **pin a specific version**.
The internal schema may change between versions.
Backward compatibility is **not guaranteed**.

Pull requests are welcome, but changes that conflict with the architectural model are unlikely to be merged.

This repository is not trying to be a universal forwarding solver for every possible network style.
It is an **architecture-first forwarding model** for one specific staged fabric model.

---

# Position in the architecture

This repository sits between the compiler and the control-plane model.

| Layer                   | Responsibility                                                                |
| ----------------------- | ----------------------------------------------------------------------------- |
| **Compiler**            | defines communication semantics and canonical staged topology                 |
| **Forwarding model**    | constructs deterministic forwarding structure from the canonical staged model |
| **Control plane model** | derives control-plane mechanisms and realization inputs                       |
| **Renderer**            | emits platform-specific configuration                                         |

Pipeline:

```text
intent
  ↓
compiler
  ↓
forwarding model
  ↓
control plane model
  ↓
renderer
```

This repository implements the **forwarding model stage**.

It is the boundary where compiled network behavior becomes **forwarding-executable structure**.

---

# What this project does

The forwarding model takes the compiler’s canonical staged site model and turns it into a deterministic forwarding description.

The compiler answers:

> what communication must exist, and which architectural stages and boundaries are valid?

The forwarding model answers:

> what forwarding structure must exist so that the compiled behavior can actually execute?

That includes things like:

* staged traversal structure
* forwarding relationships
* next-hop intent
* adjacency normalization
* routing ownership
* deterministic link identities
* operational addressing for forwarding contexts
* stage participation in executable paths
* explicit forwarding authority boundaries

The result is a **platform-independent forwarding model** that later stages can consume.

---

# What this project does not do

This project does **not**:

* generate vendor configuration
* emit Cisco configuration
* emit Junos configuration
* emit nftables rules
* emit NixOS modules
* choose BGP vs OSPF vs static routing as final platform configuration
* decide how a renderer represents forwarding on a target platform
* decide how a platform collapses co-located stages internally
* replace the control-plane model
* repair missing realization data by inventing platform facts

Those responsibilities belong downstream.

The forwarding model defines the **forwarding structure**.
Later stages decide how to derive control-plane behavior and how to realize that on actual systems.

---

# Architectural stance

The forwarding model is **platform-independent**, but it is **not architecture-neutral**.

That distinction matters.

This repository does not attempt to preserve arbitrary topology freedom all the way down.
It takes the compiler’s staged architectural model and makes it executable as deterministic forwarding structure.

Canonical traversal remains:

```text
access → downstream-selector → policy → upstream-selector → core
```

That means this project is opinionated in two ways:

1. It preserves **architectural determinism** over topology freedom.
2. It requires later stages to realize the canonical staged model, not invent a new forwarding architecture.

If a downstream system wants to co-locate stages, that is fine.
If a downstream renderer wants to map the model onto namespaces, VRFs, routing instances, containers, logical routers, physical routers, or some other execution target, that is also fine.

But downstream stages do **not** get to change the canonical stage ordering or forwarding authority model.

---

# Relationship to the compiler

The compiler defines:

* communication semantics
* communication policy intent
* canonical staged topology
* tenant and service intent
* domain structure
* architectural boundaries

The forwarding model consumes that canonical staged output and derives the deterministic forwarding structure required to make it operational.

The forwarding model therefore does **not** redefine the architecture.
It makes the architecture **forwarding-executable**.

Put differently:

* the compiler defines the architectural meaning
* the forwarding model defines the forwarding consequences of that meaning

---

# Relationship to the control-plane model

The forwarding model is **not** the control-plane model.

The forwarding model produces a deterministic forwarding description.
The control-plane model later derives:

* control-plane mechanisms
* protocol-facing realization inputs
* runtime-target-specific control data
* renderer-facing realization structure

That separation matters.

The forwarding model should describe forwarding truth in a platform-independent way.
It should not collapse into target-specific implementation details prematurely.

---

# Canonical fabric stages

The forwarding model works with the same five canonical forwarding stages established by the compiler:

| Stage                 | Responsibility                                                           |
| --------------------- | ------------------------------------------------------------------------ |
| `access`              | tenant attachment and access-edge entry                                  |
| `downstream-selector` | downstream path selection and staged aggregation before enforcement      |
| `policy`              | policy enforcement and contract-controlled traversal                     |
| `upstream-selector`   | upstream path selection toward exit-capable core                         |
| `core`                | exit anchoring, external connectivity, and top-level transport anchoring |

These are **architectural stages**, not necessarily five distinct boxes.

A realization may:

* place one stage on one node
* place multiple stages on one node
* distribute stages across multiple nodes

But the forwarding model always preserves the same stage semantics and traversal order.

---

# Why the forwarding model exists

The compiler intentionally stops before platform realization.
That is necessary, but it leaves open a critical question:

> what forwarding structure must exist so that the compiled site can actually pass packets through the canonical architecture?

That is the problem this project solves.

Without a forwarding model, downstream stages tend to accumulate ambiguity around:

* execution adjacency
* next-hop ownership
* routing authority
* path ordering
* traversal legality
* enforcement placement
* upstream and exit reachability
* stage-to-stage forwarding expectations

The forwarding model removes that ambiguity by making forwarding structure explicit and deterministic.

---

# Current limitation (important)

Today, this stage effectively assumes “one p2p transit adjacency per node pair”.
That makes it impossible to *guarantee* policy-driven “dedicated links / L2 lanes” between the same two staged nodes.

The intended direction is to make dedicated lanes a first-class, deterministic output of this stage, derived from explicit upstream intent
(e.g. which access classes are allowed to reach which uplinks / overlays), and then bound to VLANs/subifs/etc via inventory downstream.

See `TODO.md` in this repository for the lane-aware p2p plan.

---

# Forwarding responsibilities

The forwarding model derives the forwarding responsibilities implied by the compiled architecture.

Examples include:

* attachment-side forwarding roles
* staged transit forwarding
* policy-bound traversal roles
* upstream selection roles
* exit-capable forwarding roles
* routing ownership boundaries

A single realized node may host multiple responsibilities.
That does not change the model.
It only changes realization density.

---

# Traversal model

The forwarding model determines how traffic must traverse the canonical architecture so that the compiled site remains valid at runtime.

Traversal is not just cabling.
It is not just adjacency.
It is the **required forwarding order** implied by the staged architecture.

Canonical traversal:

```text
access → downstream-selector → policy → upstream-selector → core
```

This ordering exists so that:

* policy is not bypassed
* forwarding authority remains explicit
* upstream selection happens in the correct stage
* external connectivity anchors at the correct boundary
* renderers do not invent alternative traversal semantics

---

# Connectivity meaning

Connectivity in this model means **forwarding adjacency**, not physical cabling.

It represents which forwarding contexts must be able to exchange packets for the staged architecture to operate.

That means the forwarding model describes:

* adjacency needed for packet traversal
* ownership boundaries between forwarding contexts
* deterministic relationships between staged participants

It does **not** try to be a physical topology inventory.

---

# Deterministic forwarding state

For a given input, the forwarding model always produces the same forwarding state.

The model includes deterministic data such as:

* stable adjacency identities
* deterministic link ordering
* forwarding relationships
* next-hop structure
* routing ownership boundaries
* operational addressing for forwarding use
* canonical traversal expectations

The output is intended for **further model construction**, not for direct deployment.

---

# Policy handling

The forwarding model preserves the compiler’s behavioral policy meaning, but it does **not** generate policy configuration.

The communication contract remains part of the model because forwarding structure must preserve the architectural conditions under which that policy is valid.

The forwarding model therefore concerns itself with things like:

* where policy-governed traversal exists
* which forwarding paths must pass through policy stages
* which stage boundaries later consumers must preserve

It does **not**:

* generate firewall rules
* generate ACLs
* emit platform policy syntax
* reinterpret the behavioral contract as device configuration

Those decisions belong downstream.

---

# Genericity model

This project is **generic across realizations**, not generic across arbitrary network architectures.

That means:

* the forwarding model is platform-independent
* the same model may later be realized on NixOS, Cisco, Juniper, labs, or simulation systems
* different renderers may realize the same forwarding structure differently

But it does **not** mean:

* every possible topology style is accepted as-is
* downstream stages are free to invent a different stage model
* forwarding structure is allowed to become renderer-defined

The genericity boundary is therefore:

> one canonical staged fabric model, many possible realizations.

---

# Platform independence

The forwarding model is intended to stay platform-independent.

It should describe things like:

* executable forwarding structure
* staged traversal expectations
* ownership boundaries
* adjacency relationships
* forwarding identities
* operational addressing relevant to forwarding

It should not depend on:

* Linux namespaces
* NixOS options
* Cisco CLI syntax
* Junos syntax
* nftables syntax
* container runtime details
* device-specific configuration layout

Those details belong to later stages.

---

# Growth model

A network should be able to grow without replacing the forwarding model.

Examples include:

* single-core to multi-core
* single-wan to multi-wan
* single-site to multi-site
* single-enterprise to multi-enterprise
* compact co-located deployments to more distributed deployments

This project treats those as **data growth problems**, not reasons to replace the forwarding architecture.

The canonical staged model remains the same.
Only scope, cardinality, and realization complexity change.

---

# Typical output shape

The forwarding model produces structured data that later stages consume.

A typical solved site includes things like:

```text
enterprise
 └ site
    ├ communicationContract
    ├ domains
    ├ attachments
    ├ stagedTopology
    ├ transit
    ├ links
    ├ nodes
    ├ routing ownership
    ├ forwarding relationships
    ├ operational addressing
    └ traversal expectations
```

The exact schema may evolve.
Pin versions if you depend on it.

---

# Practical expectation for downstream stages

If you consume this model, the expectation is:

* preserve the canonical staged forwarding architecture
* preserve forwarding authority boundaries
* derive control-plane behavior from explicit model data
* realize co-located stages when appropriate
* do not reorder or erase the stage model
* do not invent missing forwarding intent
* do not repair incomplete architecture by guessing

A downstream stage may decide **how** to realize the forwarding model.
It may not decide that the model means something else.

---

# Running the model

Build from a compiled IR JSON (output of `network-compiler`):

```bash
nix run .#debug -- ./output-compiler-signed.json
```

Or compile + build in one step (starting from a compiler input Nix file, e.g. `intent.nix`):

```bash
nix run .#compile-and-build-forwarding-model -- ./path/to/intent.nix
```

This stage consumes compiler output (or compiler inputs via the helper app) and produces a deterministic forwarding model.

---

# Tests

Run the test suite:

```bash
./tests/test.sh
```

The test suite should validate things like:

* positive forwarding examples
* negative invariant violations
* deterministic output behavior
* canonical staged traversal preservation
* no-guessing behavior
* structural regressions

---

# ISA-88 interpretation

The architecture loosely follows ISA-88 style responsibility separation.

| ISA-88           | Meaning here                                  |
| ---------------- | --------------------------------------------- |
| Enterprise       | administrative grouping                       |
| Site             | authority boundary                            |
| Process Cell     | compiled communication behavior               |
| Unit             | forwarding execution context                  |
| Equipment Module | responsibility performed by a forwarding unit |
| Control Module   | implementation mechanism derived later        |

The compiler makes communication behavior and staged architectural boundaries explicit.
The forwarding model turns that into deterministic forwarding structure.
Later stages derive control-plane behavior and platform configuration.

---

# Non-goals

This project is not trying to be:

* a universal topology-preserving graph solver
* a vendor-native configuration generator
* a compatibility layer for every network architecture style
* a renderer that skips control-plane modeling
* a place where missing platform facts are guessed into existence

It is trying to be:

* deterministic
* explicit
* architecture-first
* forwarding-focused
* platform-independent within its architectural scope

---

# Summary

This project is a deterministic forwarding-model stage for a **fixed staged enterprise fabric model**.

It is:

* platform-independent
* architecture-opinionated
* deterministic
* intended as an intermediate model stage, not a final renderer

It takes the compiler’s canonical staged site model and turns it into a forwarding-executable representation based on the traversal model:

```text
access → downstream-selector → policy → upstream-selector → core
```

That is the point.
Not a side effect.

If that architecture fits your goals, this stage gives later consumers a stable forwarding foundation.
If it does not, this repository is probably not the right tool.
