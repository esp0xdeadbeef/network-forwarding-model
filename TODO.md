prompt TODO:
# TODO — Fix Solver Role Preservation

Problem
Solver rewrites node roles, causing declared `policy` nodes to become `access`.
This results in `policyNodeName = null`, violating renderer schema invariants.

Required Fix
Solver must preserve roles defined by the compiler input.

Rules
- Do not infer or overwrite node roles.
- Treat `role` as authoritative input.
- Validate presence of exactly one policy node per site.
- Set `policyNodeName` to that node’s name.
- Fail solver if no policy node exists.




# Newly asked TODO

- Add regression test: roles sourced from compiler provenance topology.nodes.
- Add regression test: solver preserves declared policy role.
- Add regression test: no role inference from ordering.
- Add regression test: no role overwrite for access nodes.
- Add regression test: no role overwrite for core nodes.
- Add regression test: exactly one policy node required.
- Add regression test: policyNodeName equals declared policy node.
- Add regression test: wan discovery uses topology-derived node metadata.
- Add regression test: compiled IR without site.nodes still solves.
- Add regression test: renderer schema invariants stay satisfied.
