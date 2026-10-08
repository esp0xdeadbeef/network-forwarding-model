{
  lib,
  sortedUnique,
  listOrEmpty,
  attrsOrEmpty,
}:

let
  indexes = import ./contract-index.nix {
    inherit lib sortedUnique listOrEmpty attrsOrEmpty;
  };
  inherit (indexes)
    tenantIpv6ByName
    endpointTenantNames
    relationTargetsUplink
    ;
in
{
  forUplinks =
    site: overlayUplinkNameSet: uplinkNames: uplinks:
    let
      contract = attrsOrEmpty (site.communicationContract or null);
      relations =
        if builtins.isList (contract.relations or null) then
          contract.relations
        else
          listOrEmpty (contract.allowedRelations or null);
      tenantPrefixes = tenantIpv6ByName site;

      # FS-322/FS-481: an access declares the exits it may use with `selects`;
      # the tenant is attached to that access. A tenant egressing through an
      # uplink is therefore the tenant attached to an access whose `selects`
      # resolves to that uplink, whether or not a relation pins the exit.
      topologyNodes =
        attrsOrEmpty ((attrsOrEmpty (site.topology or null)).nodes or null)
        // attrsOrEmpty (site.nodes or null);
      nodeUplinkNames =
        nodeName:
        builtins.attrNames (
          attrsOrEmpty ((attrsOrEmpty (topologyNodes.${nodeName} or null)).uplinks or null)
        );
      selectUplinkNames =
        entry:
        if builtins.isString entry then
          [ entry ]
        else if builtins.isAttrs entry then
          let
            e = attrsOrEmpty entry;
          in
          if (e.uplink or null) != null then
            [ (toString e.uplink) ]
          else if (e.surface or null) != null then
            [ (toString e.surface) ]
          else if (e.scope or null) != null then
            nodeUplinkNames (toString e.scope)
          else
            [ ]
        else
          [ ];
      selectsUplinks =
        node:
        let
          sel = (attrsOrEmpty node).selects or [ ];
        in
        if builtins.isList sel then lib.concatMap selectUplinkNames sel else [ ];
      tenantsAttachedToUplink =
        uplinkName:
        sortedUnique (
          builtins.filter (name: name != "") (
            builtins.concatMap (
              nodeName:
              let
                node = attrsOrEmpty (topologyNodes.${nodeName} or null);
              in
              if builtins.elem uplinkName (selectsUplinks node) then
                map (a: toString (a.name or "")) (
                  builtins.filter (a: builtins.isAttrs a && (a.kind or null) == "tenant") (
                    listOrEmpty (node.attachments or null)
                  )
                )
              else
                [ ]
            ) (builtins.attrNames topologyNodes)
          )
        );

      intentForUplink =
        uplinkName:
        let
          uplink = attrsOrEmpty (uplinks.${uplinkName} or null);
          translation = attrsOrEmpty (
            (attrsOrEmpty ((attrsOrEmpty (uplink.egress or null)).ipv6 or null)).translation or null
          );
          enabled = (translation.mode or null) == "nat66";
          sourceTenantNames = sortedUnique (
            tenantsAttachedToUplink uplinkName
            ++ builtins.concatMap (
              relation:
              if (relation.action or "allow") == "allow" && relationTargetsUplink uplinkName relation then
                endpointTenantNames site (relation.from or null)
              else
                [ ]
            ) relations
          );
          sourcePrefixes = sortedUnique (
            map (tenantName: tenantPrefixes.${tenantName} or null) sourceTenantNames
          );
          translatedPrefixes = sortedUnique (
            builtins.filter (prefix: prefix != null && prefix != "") (
              listOrEmpty (translation.translatedPrefixes or null)
              ++ listOrEmpty (translation.translatedAddressOrPrefix or null)
              ++ listOrEmpty (translation.translatedAddresses or null)
              ++ [
                (translation.translatedPrefix or "")
                (translation.translatedAddress or "")
                (translation.prefix or "")
                (translation.address or "")
              ]
            )
          );
        in
        if !enabled then
          null
        else
          {
            name = uplinkName;
            value = {
              mode = "nat66";
              sourcePrefixes = sourcePrefixes;
              egressSurface = uplinkName;
              providerRealized = builtins.hasAttr uplinkName overlayUplinkNameSet;
            }
            // lib.optionalAttrs (translatedPrefixes != [ ]) { inherit translatedPrefixes; }
            // lib.optionalAttrs ((translation.warning or null) != null) {
              warning = toString translation.warning;
            };
          };
      entries = builtins.filter (entry: entry != null) (map intentForUplink uplinkNames);
    in
    if entries == [ ] then { } else builtins.listToAttrs entries;
}
