{ ... }:

{
  input.site.addressPools = {
    local = "required";
    p2p = "required";
  };

  input.site.domains.tenants = "canonical";

  input.site.forwardingSemantics = {
    nodes = "accepted-as-role-hints";
    coreNodeNames = "accepted-as-role-hints";
    policyNodeName = "accepted-as-role-hints";
    upstreamSelectorNodeName = "accepted-as-role-hints";
  };

  input.site.topology.links = {
    directed = true;
    shape = "node-pairs";
    example = [
      [
        "<from-node>"
        "<to-node>"
      ]
    ];
  };

  normalization.site = {
    addressPools = {
      derived = true;
      source = "site.addressPools or site.pools";
    };
    domains.tenants = {
      derived = true;
      source = "site.domains.tenants or site.ownership.prefixes[kind=tenant]";
    };
    domains.externals = {
      derived = true;
      source = "site.domains.externals or site.policy.interfaceTags[external-*]";
    };
    attachments = {
      derived = true;
      source = "site.attachments or site.topology.nodes.*.attachments";
    };
    roles = {
      derived = true;
      source = "site.topology.nodes.*.role or site.nodes.*.role or site.units.*.role or site.forwardingSemantics";
    };
    policy.interfaceTags = {
      derived = true;
      source = "site.policy.interfaceTags merged with site.attachments and site.domains";
    };
    transit.nodePairOrdering = {
      derived = true;
      field = "site.transit.ordering";
      shape = "node-pairs";
      source = "site.topology.links";
      stage = "internal-normalized";
    };
  };

  output = {
    link.id = "link::<siteName>::<linkName>";
    node.forwarding = {
      functions = "explicit";
      traversal = {
        participates = "explicit";
        chainIndex = "explicit";
        incoming = "explicit";
        outgoing = "explicit";
      };
      responsibilities = {
        accessTermination = "explicit";
        policyEnforcement = "explicit";
        transitForwarding = "explicit";
      };
      authority = {
        attachedPrefixRouting = "explicit";
        transitRouting = "explicit";
        upstreamSelection = "explicit";
      };
    };
    node.egress.authority = "explicit";
    node.egress.upstreamSelection = "explicit";
    node.egress.exitEligible = "explicit";
    node.egress.wanInterfaces = "explicit";
    node.egress.uplinkNames = "explicit";
    route.intent = {
      field = "intent.kind";
      values = [
        "connected-reachability"
        "internal-reachability"
        "overlay-reachability"
        "uplink-learned-reachability"
        "default-reachability"
      ];
    };
    transit.adjacencies = {
      idField = "id";
      endpoint.unit = "required";
      endpoint.local.ipv4 = "required";
      endpoint.local.ipv6 = "optional";
    };
    transit.ordering = {
      field = "enterprise.<enterprise>.site.<site>.transit.ordering";
      shape = "stable-link-ids";
      source = "resolved internal transit node-pair ordering against realized p2p links";
    };
  };
}
