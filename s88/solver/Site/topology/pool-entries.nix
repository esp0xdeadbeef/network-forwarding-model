{ lib }:

let
  network = import ../../../../lib/model/network-utils.nix { inherit lib; };
  common = import ./common.nix { inherit lib; };
in
rec {
  explicitLoopbackFromSite =
    site: unitName:
    let
      base = common.nodeFromSite site unitName;
    in
    if base ? loopback then
      common.normalizeLoopback base.loopback
    else if site ? routerLoopbacks && site.routerLoopbacks ? "${unitName}" then
      common.normalizeLoopback site.routerLoopbacks.${unitName}
    else
      null;

  userPrefixEntriesFromNodes =
    nodes:
    lib.concatMap (
      nodeName:
      let
        node = nodes.${nodeName};
        nets = network.networksOfRaw {
          extraExcluded = [
            "containers"
            "uplinks"
            "loopback"
            "routingDomain"
          ];
        } node;
      in
      lib.concatMap (
        netName:
        let
          net = nets.${netName};
        in
        lib.flatten [
          (lib.optional (net ? ipv4 && net.ipv4 != null) {
            family = 4;
            cidr = toString net.ipv4;
            label = "nodes.${nodeName}.networks.${netName}.ipv4";
          })
          (lib.optional (net ? ipv6 && net.ipv6 != null) {
            family = 6;
            cidr = toString net.ipv6;
            label = "nodes.${nodeName}.networks.${netName}.ipv6";
          })
        ]
      ) (builtins.attrNames nets)
    ) (builtins.attrNames nodes);

  explicitLoopbackEntriesFromUnits =
    site: unitNames:
    lib.concatMap (
      unitName:
      let
        lb = explicitLoopbackFromSite site unitName;
      in
      if lb == null then
        [ ]
      else
        lib.flatten [
          (lib.optional ((lb.ipv4 or null) != null) {
            family = 4;
            addr = toString lb.ipv4;
            label = "nodes.${unitName}.loopback.ipv4";
          })
          (lib.optional ((lb.ipv6 or null) != null) {
            family = 6;
            addr = toString lb.ipv6;
            label = "nodes.${unitName}.loopback.ipv6";
          })
        ]
    ) unitNames;

  wanAddressEntriesFromLinks =
    links:
    lib.concatMap (
      linkName:
      let
        link = links.${linkName};
        eps = link.endpoints or { };
      in
      lib.concatMap (
        nodeName:
        let
          endpoint = eps.${nodeName};
        in
        lib.flatten [
          (lib.optional ((endpoint.addr4 or null) != null) {
            family = 4;
            addr = toString endpoint.addr4;
            label = "links.${linkName}.endpoints.${nodeName}.addr4";
          })
          (lib.optional ((endpoint.peerAddr4 or null) != null) {
            family = 4;
            addr = toString endpoint.peerAddr4;
            label = "links.${linkName}.endpoints.${nodeName}.peerAddr4";
          })
          (lib.optional ((endpoint.addr6 or null) != null) {
            family = 6;
            addr = toString endpoint.addr6;
            label = "links.${linkName}.endpoints.${nodeName}.addr6";
          })
          (lib.optional ((endpoint.peerAddr6 or null) != null) {
            family = 6;
            addr = toString endpoint.peerAddr6;
            label = "links.${linkName}.endpoints.${nodeName}.peerAddr6";
          })
        ]
      ) (builtins.attrNames eps)
    ) (builtins.attrNames links);
}
