{ lib, self ? { outPath = ./.; }, ... }:

let
  cidrNormalize = import (self.outPath + "/implementation/lib/net/cidr-normalize.nix") { inherit lib self; };
  network = import ./network-utils.nix { inherit lib self; };

  canonicalCidr = cidrNormalize.canonicalCidr;

  mkConnectedRoute = dst: {
    dst = canonicalCidr dst;
    proto = "connected";
    intent = {
      kind = "connected-reachability";
    };
  };

  networksOf =
    { extraExcluded ? [
        "containers"
        "uplinks"
      ]
    ,
    }:
    network.networksOfNode { inherit extraExcluded; };

  prefixEntriesFromIfaces =
    node:
    let
      ifs = node.interfaces or { };
      ifNames = builtins.attrNames ifs;
    in
    lib.concatMap
      (
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
          (map
            (p: {
              family = 6;
              dst = canonicalCidr p;
            })
            (iface.ra6Prefixes or [ ]))
        ]
      )
      ifNames;

  prefixEntriesFromNetworks =
    node:
    let
      nets = (networksOf { }) node;
      netNames = builtins.attrNames nets;
      runtimeAuthorityClass =
        p:
        if (p.authorityClass or null) != null then
          toString p.authorityClass
        else if (p.perTenantPrefixLength or null) == 128 then
          "host-only-provider-prefix"
        else
          "routed-client-prefix";
    in
    lib.concatMap
      (
        netName:
        let
          net = nets.${netName};
          ownsPrefix = (net.gateway or true) != false;
        in
        lib.flatten [
          (lib.optional (ownsPrefix && net ? ipv4 && net.ipv4 != null) {
            family = 4;
            dst = canonicalCidr net.ipv4;
            netName = netName;
          })
          (lib.optional (ownsPrefix && net ? publicIpv4 && net.publicIpv4 != null) {
            family = 4;
            dst = canonicalCidr net.publicIpv4;
            netName = netName;
            kind = "routed-public-ipv4";
            authorityClass = "routed-public-ipv4";
            source = "domains.tenants.publicIpv4";
          })
          (lib.optional (ownsPrefix && net ? ipv6 && net.ipv6 != null) {
            family = 6;
            dst = canonicalCidr net.ipv6;
            netName = netName;
          })
          (map
            (p: {
              family = 6;
              dst = canonicalCidr p;
              netName = netName;
            })
            (lib.optionals ownsPrefix (net.ra6Prefixes or [ ])))
          (map
            (p: {
              family = 6;
              sourceFile = p.sourceFile;
              prefixName = p.name or null;
              netName = netName;
              kind = "runtime-routed-prefix";
              authorityClass = runtimeAuthorityClass p;
              delegatedPrefixLength = p.delegatedPrefixLength or 64;
              perTenantPrefixLength = p.perTenantPrefixLength or 64;
              slot = p.slot or 0;
            } // lib.optionalAttrs ((p.prefixPostfix or null) != null) {
              prefixPostfix = p.prefixPostfix;
            })
            (lib.optionals ownsPrefix (
              lib.filter (p: builtins.isAttrs p && (p.sourceFile or null) != null) (net.routedPrefixes or [ ])
            )))
        ]
      )
      netNames;

  ownConnectedPrefixes =
    node:
    builtins.foldl' (acc: e: if e ? dst then acc // { "${toString e.family}|${e.dst}" = true; } else acc) { } (
      prefixEntriesFromIfaces node ++ prefixEntriesFromNetworks node
    );

  prefixSetFromP2pIfaces =
    node:
    let
      ifs = node.interfaces or { };
      ifNames = builtins.attrNames ifs;
    in
    builtins.foldl'
      (
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
      )
      { }
      ifNames;

  prefixSetFromNetworks =
    node:
    builtins.foldl'
      (
        acc: e:
        acc
        // {
          "${toString e.family}|${if e ? dst then e.dst else "source:${e.sourceFile}"}" =
            e // {
              family = e.family;
              netName = e.netName or null;
            };
        }
      )
      { }
      (prefixEntriesFromNetworks node);

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
