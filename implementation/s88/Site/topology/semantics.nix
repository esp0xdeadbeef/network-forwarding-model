{
  lib,
  self ? {
    outPath = ./.;
  },
  ...
}:

let
  selection = import ./semantic-selection.nix { inherit lib self; };
  semanticNode = import ./semantic-node.nix { inherit lib self; };

  inherit (selection)
    coreNodeNamesFor
    externalDomainNamesFromSite
    maybeOne
    policyNodeNameFor
    roleOfFor
    siteUplinkCoreNamesFor
    siteUplinkNamesFor
    sortedUnique
    upstreamSelectorNodeNameFor
    ;

  annotateSite =
    {
      site,
      rolesResult ? null,
      wanResult ? null,
    }:
    let
      nodes = site.nodes or { };
      nodeNames = sortedUnique (builtins.attrNames nodes);

      roleOf = roleOfFor { inherit nodes rolesResult; };
      coreNodeNames = coreNodeNamesFor { inherit site nodeNames roleOf; };
      policyNodeName = policyNodeNameFor { inherit site nodeNames roleOf; };
      upstreamSelectorNodeName = upstreamSelectorNodeNameFor { inherit site nodeNames roleOf; };
      siteExternalDomains = externalDomainNamesFromSite site;
      siteUplinkCoreNames = siteUplinkCoreNamesFor { inherit site wanResult; };
      siteUplinkNames = siteUplinkNamesFor { inherit site wanResult siteExternalDomains; };

      nodeSemantics = builtins.mapAttrs (
        nodeName: node:
        semanticNode.build {
          inherit
            node
            nodeName
            site
            siteExternalDomains
            siteUplinkCoreNames
            siteUplinkNames
            ;
          role = roleOf nodeName;
        }
      ) nodes;

      traversalParticipantNodeNames = sortedUnique (
        lib.filter (
          name: ((nodeSemantics.${name}.traversalParticipation.participates or false) == true)
        ) nodeNames
      );
      isWanFallbackCore =
        name:
        let
          node = nodes.${name} or { };
          uplinks = node.uplinks or { };
        in
        builtins.any (
          uplinkName:
          let
            uplink = uplinks.${uplinkName} or { };
            prefixes = (uplink.ipv4 or [ ]) ++ (uplink.ipv6 or [ ]);
          in
          builtins.elem "0.0.0.0/0" prefixes || builtins.elem "::/0" prefixes
        ) (builtins.attrNames uplinks);
      dnsAccessNodeNames = sortedUnique (lib.filter (name: roleOf name == "access") nodeNames);
      dnsCoreNodeNames = sortedUnique coreNodeNames;
      dnsNonWanCoreNodeNames = sortedUnique (
        lib.filter (name: !(isWanFallbackCore name)) dnsCoreNodeNames
      );
      dnsWanCoreNodeNames = sortedUnique (lib.filter isWanFallbackCore dnsCoreNodeNames);

      siteEgressIntent = {
        eligibleNodeNames = sortedUnique (siteUplinkCoreNames ++ (maybeOne upstreamSelectorNodeName));
        exitNodeNames = sortedUnique siteUplinkCoreNames;
        explicit = true;
        externalDomains = siteExternalDomains;
        uplinkCoreNodeNames = sortedUnique siteUplinkCoreNames;
        upstreamSelectorNodeName = upstreamSelectorNodeName;
      };

      forwardingSemantics = {
        coreNodeNames = coreNodeNames;
        dns = {
          explicit = true;
          serviceNodeNames = sortedUnique (dnsAccessNodeNames ++ dnsCoreNodeNames);
          resolverPreferenceNodeNames = dnsAccessNodeNames ++ dnsNonWanCoreNodeNames ++ dnsWanCoreNodeNames;
          accessNodeNames = dnsAccessNodeNames;
          nonWanCoreNodeNames = dnsNonWanCoreNodeNames;
          wanFallbackNodeNames = dnsWanCoreNodeNames;
        };
        explicit = true;
        nodes = nodeSemantics;
        policyNodeName = policyNodeName;
        traversalParticipantNodeNames = traversalParticipantNodeNames;
        upstreamSelectorNodeName = upstreamSelectorNodeName;
      };

      annotatedNodes = builtins.mapAttrs (name: node: node // (nodeSemantics.${name} or { })) nodes;
    in
    site
    // {
      coreNodeNames = coreNodeNames;
      policyNodeName = policyNodeName;
      upstreamSelectorNodeName = upstreamSelectorNodeName;
      uplinkCoreNames = siteUplinkCoreNames;
      uplinkNames = siteUplinkNames;
      egressIntent = siteEgressIntent;
      forwardingSemantics = forwardingSemantics;
      nodes = annotatedNodes;
    };

in
{
  inherit annotateSite;
  build = args: annotateSite args;
}
