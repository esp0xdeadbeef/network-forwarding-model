# Implementation Plan

Goal: make the forwarding-model the only place where S88 semantic intent becomes forwarding-executable structure, without leaking renderer concerns or relying on downstream repair.

## Current S88 posture

This repo already follows the right direction:

- compiler meaning is consumed, not redefined
- canonical traversal is preserved
- dedicated lanes are derived here
- overlays become forwarding reachability here

The remaining gaps are mostly about making that contract explicit enough that CPM and renderers do not need compatibility logic.

## Main gaps

1. Forwarding output schema is richer than the README explains.
   - Lane naming, overlay reachability, route intent kinds, and logical interface identities are real contract data, but the README still speaks at a higher level than the code.

2. Overlay forwarding semantics are under-documented.
   - `terminateOn`, `overlayReachability`, route ownership, and overlay logical interfaces should be presented as first-class S88 forwarding output.

3. Route-intent categories need to be formalized.
   - Static routes, external reachability, overlay reachability, and lane-derived routes should be described as explicit forwarding classes.

4. Downstream inventory requirements are referenced, but not as a precise handoff contract.
   - CPM should not need to “discover” what forwarding-model intended to be realizable.

## Work items

1. Extend `README.md` with an explicit forwarding contract section.
   - Document:
     - stable lane naming
     - logical vs physical interface identities
     - overlay interface generation
     - route intent kinds
     - ownership fields that CPM must consume

2. Define a canonical “realization-required” subset.
   - Make it obvious which forwarding outputs must be bound by inventory in CPM.
   - This includes lane links, tenant attachments, overlay terminations, uplink-facing nodes, and stage nodes.

3. Harden overlay forwarding tests.
   - Keep dedicated tests for multi-site overlays.
   - Add assertions for overlay interface identity and route ownership on termination nodes.

4. Remove remaining ambiguity between forwarding truth and realization truth.
   - README should state that forwarding-model never emits bridge names, host uplink mapping, VLAN attachment choices, or container placement.

5. Document how S88 scaling is expected to work.
   - multi-enterprise
   - multi-site
   - multi-uplink
   - multi-overlay
   - co-located stages

## Exit criteria

- CPM can consume forwarding output without adding semantic shims.
- Overlay and lane outputs are described as normative forwarding artifacts.
- The forwarding-model is clearly the only stage that derives forwarding structure from compiler intent.
- Renderer-specific concerns are absent from both code paths and README contract language.

## Test impact

- Keep the full test sweep.
- Add one golden assertion set for lane naming invariants.
- Keep one dedicated multi-site overlay forwarding test in-tree.
