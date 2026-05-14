{ lib, self ? { outPath = ./.; }, ... }:

let
  ip = import (self.outPath + "/lib/net/ip-utils.nix") { inherit lib self; };

  mkEndpoint =
    nodeName: ep:
    let
      local4 = if (ep.addr4 or null) == null then null else ip.stripMask ep.addr4;
      local6 = if (ep.addr6 or null) == null then null else ip.stripMask ep.addr6;
    in
    if local4 == null then
      throw ''
        network-forwarding-model: transit adjacency endpoint requires IPv4 local address

        link: ${toString (ep.interface or "<unknown-link>")}
        unit: ${toString nodeName}
        addr4: ${toString (ep.addr4 or "null")}
      ''
    else
      {
        unit = nodeName;
        local = {
          ipv4 = local4;
        }
        // lib.optionalAttrs (local6 != null) { ipv6 = local6; };
      };

in
links:
let
  p2pLinkNames = lib.filter (linkName: (links.${linkName}.kind or null) == "p2p") (
    lib.sort (a: b: a < b) (builtins.attrNames links)
  );

  mkAdjacency =
    linkName:
    let
      link = links.${linkName};
      linkId = link.id or null;
      endpoints = link.endpoints or { };
      nodeNames = lib.sort (a: b: a < b) (builtins.attrNames endpoints);

      _two =
        if builtins.length nodeNames == 2 then
          true
        else
          throw ''
            network-forwarding-model: transit adjacency must have exactly 2 endpoints

            link: ${linkName}
            endpoints: ${builtins.toJSON nodeNames}
          '';

      _id =
        if linkId == null then
          throw ''
            network-forwarding-model: transit adjacency is missing stable link identity

            link: ${linkName}
          ''
        else
          true;
    in
    builtins.seq _two (
      builtins.seq _id {
        id = toString linkId;
        name = linkName;
        kind = "p2p";
        link = linkName;
        members = nodeNames;
        endpoints = map (nodeName: mkEndpoint nodeName endpoints.${nodeName}) nodeNames;
      }
      // lib.optionalAttrs ((link.lane or null) != null) { lane = link.lane; }
      // lib.optionalAttrs (builtins.isAttrs (link.laneMeta or null)) { laneMeta = link.laneMeta; }
      // lib.optionalAttrs (builtins.isList (link.uplinks or null)) { uplinks = link.uplinks; }
      // lib.optionalAttrs ((link.overlay or null) != null) { overlay = link.overlay; }
    );
in
map mkAdjacency p2pLinkNames
