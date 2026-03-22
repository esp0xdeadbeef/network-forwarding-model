# TODO — Solver output consistency

## Problem

The solver output still contains one consistency issue even after `communicationContract.interfaceTags` was fixed.

The current solver output models `upstream-selector` as a real node in the emitted topology, but also emits `upstreamSelectorNodeName` pointing at a core node in single-core cases.

Observed result in solver output:

* `topology.nodes.<name>.role = "upstream-selector"` exists
* `transit.ordering` still traverses that upstream-selector node
* `links` still contains realized p2p links through that upstream-selector node
* `upstreamSelectorNodeName` may still point to the core node instead of the actual upstream-selector node

That creates an ambiguous contract for downstream consumers.

There is also a second consistency issue:

* `transit.adjacencies` is emitted separately from realized `links`
* emitted adjacency endpoint addresses can drift from the actual realized p2p link endpoints

That causes downstream confusion because the solver output exposes two topology representations that can disagree.

## Required behavior

When the solver emits a topology that contains a node with role `upstream-selector`, it must preserve that identity in the final normalized / canonical / signed solver output at:

`enterprise.<name>.site.<name>.upstreamSelectorNodeName`

That field must point to the actual emitted node whose role is `upstream-selector`.

The solver must also derive:

`enterprise.<name>.site.<name>.transit.adjacencies`

from the realized p2p links already present in:

`enterprise.<name>.site.<name>.links`

## Acceptance criteria

* [ ] `upstreamSelectorNodeName` always names the actual emitted upstream-selector node when one exists.
* [ ] `upstreamSelectorNodeName` never points to a node whose emitted role is `core`.
* [ ] `transit.adjacencies` is derived from realized `links`, not from a separate allocator or stale pre-realization view.
* [ ] Every endpoint address in `transit.adjacencies` matches the corresponding endpoint address in emitted `links`.
* [ ] `topology.nodes`, `transit.ordering`, `transit.adjacencies`, and `links` describe the same topology.
* [ ] No separate fallback meaning is hidden inside `upstreamSelectorNodeName`.

## Tests to add upstream

* [ ] Fixture with a real `upstream-selector` node and a single core.
* [ ] Assertion that `upstreamSelectorNodeName` equals the emitted node whose role is `upstream-selector`.
* [ ] Assertion that `topology.nodes[upstreamSelectorNodeName].role == "upstream-selector"`.
* [ ] Assertion that every emitted `transit.adjacencies[*]` endpoint matches the corresponding realized p2p link endpoint.
* [ ] Regression test proving single-core mode does not silently rewrite selector identity to the core node.
* [ ] Regression test proving adjacency addresses are not emitted from a stale numbering path.

## Likely fix area

Investigate the solver path that determines:

* `upstreamSelectorNodeName`
* `transit.adjacencies`
* final site-level normalized output assembly

The bug is likely in one of these places:

* fallback logic that rewrites selector identity to the first core node
* code that treats single-core routing behavior as node identity
* adjacency emission code that is not derived from realized `links`
* explicit attrset reconstruction of the final site object

## Minimal regression checks

This should evaluate to `true` after the fix:

jq -e '
.enterprise
| to_entries[]
| .value.site
| to_entries[]
| .value as $s
| ($s.upstreamSelectorNodeName == null)
or
($s.topology.nodes[$s.upstreamSelectorNodeName].role == "upstream-selector")
' output-solver-signed.json

And this should show matching transit-versus-links data for a fixture site:

jq '
.enterprise.esp0xdeadbeef.site["site-a"] as $s
| {
transit: $s.transit.adjacencies,
links: $s.links
}
' output-solver-signed.json

## Definition of done

* [ ] Solver output contains a truthful `upstreamSelectorNodeName`
* [ ] Solver output derives `transit.adjacencies` from realized `links`
* [ ] Downstream consumers no longer receive contradictory topology representations for the s

