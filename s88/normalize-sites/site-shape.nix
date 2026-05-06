{
  getAttrPathOr,
  hasAttrPath,
}:

let
  siteAttachmentsFromTopology =
    site:
    let
      nodes = getAttrPathOr [ "topology" "nodes" ] { } site;
      nodeNames = builtins.attrNames nodes;
    in
    builtins.concatLists (
      builtins.map (
        nodeName:
        builtins.map (attachment: attachment // { unit = nodeName; }) (nodes.${nodeName}.attachments or [ ])
      ) nodeNames
    );

  siteCoreNodeNamesFromTopology =
    site:
    let
      nodes = getAttrPathOr [ "topology" "nodes" ] { } site;
      nodeNames = builtins.attrNames nodes;
    in
    builtins.filter (nodeName: (nodes.${nodeName}.role or null) == "core") nodeNames;

  normalizeCommunicationContract =
    site:
    let
      cc = site.communicationContract or { };
    in
    {
      allowedRelations =
        if cc ? allowedRelations then
          cc.allowedRelations
        else if cc ? relations then
          cc.relations
        else
          [ ];
      services = cc.services or [ ];
      trafficTypes = cc.trafficTypes or [ ];
    };

  normalizeAddressPools =
    site:
    let
      explicitAddressPools = site.addressPools or null;
      explicitLocal = if explicitAddressPools == null then null else explicitAddressPools.local or null;
      explicitP2p = if explicitAddressPools == null then null else explicitAddressPools.p2p or null;

      derivedLocal =
        if hasAttrPath [ "pools" "loopback" ] site then
          site.pools.loopback
        else if hasAttrPath [ "pools" "local" ] site then
          site.pools.local
        else
          { };

      derivedP2p = if hasAttrPath [ "pools" "p2p" ] site then site.pools.p2p else { };
    in
    {
      local = if explicitLocal != null && explicitLocal != { } then explicitLocal else derivedLocal;
      p2p = if explicitP2p != null && explicitP2p != { } then explicitP2p else derivedP2p;
    };

  normalizeTopology =
    site:
    let
      topology = site.topology or { };
    in
    {
      nodes = topology.nodes or { };
      links = topology.links or [ ];
    };

  normalizeLinks = site: if site ? links then site.links else { };

  normalizeNodes = site: if site ? nodes then site.nodes else { };

in
{
  inherit
    normalizeAddressPools
    normalizeCommunicationContract
    normalizeLinks
    normalizeNodes
    normalizeTopology
    siteAttachmentsFromTopology
    siteCoreNodeNamesFromTopology
    ;
}
