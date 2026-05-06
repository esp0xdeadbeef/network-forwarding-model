{ lib }:

let
  selection = import ./semantic-selection.nix { inherit lib; };
  semanticNode = import ./semantic-node.nix { inherit lib; };

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
