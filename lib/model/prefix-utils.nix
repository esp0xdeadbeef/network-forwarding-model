{ lib }:

let
  cidrNormalize = import ../net/cidr-normalize.nix { inherit lib; };
  network = import ./network-utils.nix { inherit lib; };

  canonicalCidr = cidrNormalize.canonicalCidr;

  mkConnectedRoute = dst: {
    dst = canonicalCidr dst;
    proto = "connected";
    intent = {
      kind = "connected-reachability";
    };
  };

  networksOf =
    {
      extraExcluded ? [
        "containers"
        "uplinks"
      ],
    }:
    network.networksOfNode { inherit extraExcluded; };

  prefixEntriesFromIfaces =
    node:
    let
      ifs = node.interfaces or { };
      ifNames = builtins.attrNames ifs;
    in
    lib.concatMap (
      ifName:
      let
        iface = ifs.${ifName};
      in
      lib.flatten [
        (lib.optional (iface ? addr4 && iface.addr4 != null) {
          family = 4;
          dst = canonicalCidr iface.addr4;
        })
        (lib.optional (iface ? addr6 && iface.addr6 != null) {
          family = 6;
          dst = canonicalCidr iface.addr6;
        })
        (lib.optional (iface ? addr6Public && iface.addr6Public != null) {
          family = 6;
          dst = canonicalCidr iface.addr6Public;
        })
        (map (p: {
          family = 6;
          dst = canonicalCidr p;
        }) (iface.ra6Prefixes or [ ]))
      ]
    ) ifNames;

  prefixEntriesFromNetworks =
    node:
    let
      nets = (networksOf { }) node;
      netNames = builtins.attrNames nets;
    in
    lib.concatMap (
      netName:
      let
        net = nets.${netName};
      in
      lib.flatten [
        (lib.optional (net ? ipv4 && net.ipv4 != null) {
          family = 4;
          dst = canonicalCidr net.ipv4;
          netName = netName;
        })
        (lib.optional (net ? ipv6 && net.ipv6 != null) {
          family = 6;
          dst = canonicalCidr net.ipv6;
          netName = netName;
        })
      ]
    ) netNames;

  ownConnectedPrefixes =
    node:
    builtins.foldl' (acc: e: acc // { "${toString e.family}|${e.dst}" = true; }) { } (
      prefixEntriesFromIfaces node ++ prefixEntriesFromNetworks node
    );

  prefixSetFromP2pIfaces =
    node:
    let
      ifs = node.interfaces or { };
      ifNames = builtins.attrNames ifs;
    in
    builtins.foldl' (
      acc: ifName:
      let
        iface = ifs.${ifName};
      in
      if (iface.kind or null) != "p2p" then
        acc
      else
        acc
        // (lib.optionalAttrs (iface ? addr4 && iface.addr4 != null) {
          "4|${canonicalCidr iface.addr4}" = {
            family = 4;
            dst = canonicalCidr iface.addr4;
          };
        })
        // (lib.optionalAttrs (iface ? addr6 && iface.addr6 != null) {
          "6|${canonicalCidr iface.addr6}" = {
            family = 6;
            dst = canonicalCidr iface.addr6;
          };
        })
    ) { } ifNames;

  prefixSetFromNetworks =
    node:
    builtins.foldl' (
      acc: e:
      acc
      // {
        "${toString e.family}|${e.dst}" = {
          family = e.family;
          dst = e.dst;
          netName = e.netName or null;
        };
      }
    ) { } (prefixEntriesFromNetworks node);

in
{
  inherit
    canonicalCidr
    mkConnectedRoute
    networksOf
    prefixEntriesFromIfaces
    prefixEntriesFromNetworks
    ownConnectedPrefixes
    prefixSetFromP2pIfaces
    prefixSetFromNetworks
    ;
}
