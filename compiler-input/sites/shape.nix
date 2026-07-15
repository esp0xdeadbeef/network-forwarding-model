{ getAttrPathOr
, hasAttrPath
,
}:

let
  siteAttachmentsFromTopology =
    site:
    let
      nodes = getAttrPathOr [ "topology" "nodes" ] { } site;
      nodeNames = builtins.attrNames nodes;
    in
    builtins.concatLists (
      builtins.map
        (
          nodeName:
          builtins.map (attachment: attachment // { unit = nodeName; }) (nodes.${nodeName}.attachments or [ ])
        )
        nodeNames
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
      rawRelations =
        if cc ? allowedRelations then
          cc.allowedRelations
        else if cc ? relations then
          cc.relations
        else
          [ ];
    in
    {
      allowedRelations = builtins.map
        (rel:
          let
            relationId = if builtins.isString (rel.id or null) && rel.id != "" then rel.id else "<unknown>";
            topLevelPresent = rel ? returnBehavior;
            topLevel = rel.returnBehavior or null;
            publicIngressAuthority = rel.publicIngressTupleAuthority or null;
            nestedPresent =
              builtins.isAttrs publicIngressAuthority && publicIngressAuthority ? returnBehavior;
            nested = if nestedPresent then publicIngressAuthority.returnBehavior else null;
            validReturnBehavior = value: builtins.isString value && value != "";
            # FS-180-HDS-010-SDS-010-SMS-040 Negative case 3: the recognized
            # return-behavior vocabulary. Values outside this set (e.g.
            # "asymmetric", "hairpin", "unknown") must be rejected with a
            # diagnostic naming the value and relation ID, never silently
            # treated as absent or one-way.
            recognizedReturnBehaviors = [ "symmetric" "one-way" "stateful-return" ];
            recognizedReturnBehavior = value: builtins.elem value recognizedReturnBehaviors;
            fail = reason:
              throw "FS-180-HDS-010-SDS-010-SMS-010: allow relation '${relationId}' ${reason}";
            failUnrecognized = position: value:
              throw "FS-180-HDS-010-SDS-010-SMS-040: allow relation '${relationId}' has an unrecognized ${position} returnBehavior '${value}'; recognized values: ${builtins.concatStringsSep ", " recognizedReturnBehaviors}";
          in
          if (rel.action or null) != "allow" then
            rel
          else if topLevelPresent && !validReturnBehavior topLevel then
            fail "has an invalid top-level returnBehavior"
          else if nestedPresent && !validReturnBehavior nested then
            fail "has an invalid publicIngressTupleAuthority.returnBehavior"
          else if topLevelPresent && !recognizedReturnBehavior topLevel then
            failUnrecognized "top-level" topLevel
          else if nestedPresent && !recognizedReturnBehavior nested then
            failUnrecognized "publicIngressTupleAuthority" nested
          else if topLevelPresent && nestedPresent && topLevel != nested then
            fail "has conflicting returnBehavior values '${topLevel}' and '${nested}'"
          else if topLevelPresent then
            rel
          else if nestedPresent then
            rel // { returnBehavior = nested; }
          else if (rel ? bidirectional && rel.bidirectional) then
            let bFromKind = (rel.from or {}).kind or null;
                bToKind = (rel.to or {}).kind or null;
            in if bFromKind == "tenant-set" && bToKind == "tenant-set" then
              rel  # local tenant-to-tenant: one-way even with bidirectional per FS-640/FS-620
            else
              rel // { returnBehavior = "symmetric"; }
          else
            let fromKind = (rel.from or {}).kind or null;
                toKind = (rel.to or {}).kind or null;
            in if fromKind == "tenant-set" && toKind == "tenant-set" then
              rel  # local tenant-to-tenant: one-way by default per FS-640/FS-620
            else
              rel // { returnBehavior = "symmetric"; }
        )
        rawRelations;
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
