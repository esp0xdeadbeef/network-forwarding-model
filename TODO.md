# TODO

[ ] Audit legacy helper code
    - verify unused helpers in prefix-utils.nix
    - remove routingDomain stripping logic if no longer used

[ ] Decide fate of solver query layer
    Currently exported:
        query.multiWan
        query.topology
        query.wan

    Either:
        - move lib/query/* to renderer/tooling
        - or formally keep query as a read-only solver inspection layer.

Acceptance condition:
    Solver output must remain fully renderer-consumable using only:

        enterprise.<enterprise>.site.<site>.policyIntent
        enterprise.<enterprise>.site.<site>.tenantPrefixOwners
        enterprise.<enterprise>.site.<site>.uplinkNames
        enterprise.<enterprise>.site.<site>.policyNodeName
        enterprise.<enterprise>.site.<site>.nodes
        enterprise.<enterprise>.site.<site>.links

    Renderer must not depend on meta.provenance or compiler artifacts.
