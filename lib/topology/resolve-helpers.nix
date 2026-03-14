{ lib }:

let
  ip = import ../net/ip-utils.nix { inherit lib; };
  prefix = import ../model/prefix-utils.nix { inherit lib; };
  routes = import ../model/routes.nix { inherit lib; };

  splitCidr = ip.splitCidr;
  canonicalCidr = prefix.canonicalCidr;
  ifaceRoutes = routes.ifaceRoutes;
  mkConnectedRoute = prefix.mkConnectedRoute;
  networksOf = prefix.networksOf { };

  hasPrefixLength =
    cidrStr: want:
    let
      c = splitCidr cidrStr;
    in
    c.prefix == want;

  logicalInterfaceNameFor = netName: "tenant-${toString netName}";

  overlayInterfaceNameFor = overlayName: "overlay-${toString overlayName}";

  mkLogicalIface =
    {
      nodeName,
      ifName,
      netName,
      net,
    }:
    let
      subnet4 = if net ? ipv4 && net.ipv4 != null then canonicalCidr net.ipv4 else null;
      subnet6 = if net ? ipv6 && net.ipv6 != null then canonicalCidr net.ipv6 else null;
      tenantName = if net ? name && net.name != null then toString net.name else toString netName;
    in
    {
      name = ifName;
      node = nodeName;
      interface = ifName;
      link = ifName;
      logical = true;
      virtual = true;
      l2 = false;
      kind = net.kind or "tenant";
      type = "logical";
      carrier = "logical";

      tenant = tenantName;
      network = {
        name = tenantName;
        kind = net.kind or "tenant";
        ipv4 = subnet4;
        ipv6 = subnet6;
      };

      gateway = false;

      addr4 = subnet4;
      peerAddr4 = null;
      addr6 = subnet6;
      peerAddr6 = null;
      addr6Public = null;

      subnet4 = subnet4;
      subnet6 = subnet6;

      ll6 = null;
      uplink = null;
      upstream = null;
      overlay = null;

      routes = {
        ipv4 = lib.optional (subnet4 != null) (mkConnectedRoute subnet4);
        ipv6 = lib.optional (subnet6 != null) (mkConnectedRoute subnet6);
      };

      ra6Prefixes = [ ];
      acceptRA = false;
      dhcp = false;
    };

  mkOverlayIface =
    {
      nodeName,
      ifName,
      overlayName,
      overlay ? { },
      reachability ? null,
    }:
    let
      reach0 = if reachability != null && builtins.isAttrs reachability then reachability else { };

      routes4 = reach0.routes4 or [ ];
      routes6 = reach0.routes6 or [ ];
    in
    {
      name = ifName;
      node = nodeName;
      interface = ifName;
      link = ifName;
      logical = true;
      virtual = true;
      l2 = false;
      kind = overlay.kind or "overlay";
      type = "overlay";
      carrier = "logical";

      gateway = false;

      addr4 = null;
      peerAddr4 = null;
      addr6 = null;
      peerAddr6 = null;
      addr6Public = null;

      subnet4 = null;
      subnet6 = null;

      ll6 = null;
      uplink = null;
      upstream = null;
      overlay = overlayName;

      transport = lib.optionalAttrs (builtins.isAttrs overlay) (
        (builtins.removeAttrs overlay [
          "terminateOn"
          "terminatesOn"
          "terminatedOn"
          "unit"
          "node"
          "name"
        ])
        // {
          peerSite = reach0.peerSite or null;
        }
      );

      routes = {
        ipv4 = routes4;
        ipv6 = routes6;
      };

      ra6Prefixes = [ ];
      acceptRA = false;
      dhcp = false;
    };

  mkIfaceBase =
    {
      linkName,
      link,
      ep,
    }:
    let
      rawAddr4 = ep.addr4 or null;
      useDhcp = rawAddr4 != null && !(hasPrefixLength rawAddr4 0) && !(hasPrefixLength rawAddr4 31);

      finalAddr4 = if useDhcp then null else rawAddr4;
      finalDhcp = if useDhcp then true else (ep.dhcp or false);

      rawAddr6 = ep.addr6 or null;
      rawAddr6Public = ep.addr6Public or null;

      ra6 = ep.ra6Prefixes or [ ];

      connected4 = if finalAddr4 == null then [ ] else [ (mkConnectedRoute finalAddr4) ];

      connected6 =
        (lib.optional (rawAddr6 != null) (mkConnectedRoute rawAddr6))
        ++ (lib.optional (rawAddr6Public != null) (mkConnectedRoute rawAddr6Public))
        ++ (map mkConnectedRoute ra6);
    in
    {
      link = linkName;
      kind = link.kind or null;
      type = link.type or (link.kind or null);
      carrier = link.carrier or "lan";

      tenant = ep.tenant or null;
      gateway = ep.gateway or false;

      addr4 = finalAddr4;
      peerAddr4 = ep.peerAddr4 or null;
      addr6 = rawAddr6;
      peerAddr6 = ep.peerAddr6 or null;
      addr6Public = rawAddr6Public;

      ll6 = ep.ll6 or null;

      uplink = ep.uplink or link.uplink or link.upstream or null;
      upstream = link.upstream or ep.uplink or null;
      overlay = link.overlay or null;

      uplinkRoutes4 = ep.uplinkRoutes4 or [ ];
      uplinkRoutes6 = ep.uplinkRoutes6 or [ ];

      routes = {
        ipv4 = connected4 ++ (ep.routes4 or [ ]);
        ipv6 = connected6 ++ (ep.routes6 or [ ]);
      };
      ra6Prefixes = ra6;

      acceptRA = ep.acceptRA or false;
      dhcp = finalDhcp;
    };

  mergePrebuiltIface =
    generic: prebuilt:
    generic
    // prebuilt
    // {
      link = generic.link;
      kind = prebuilt.kind or generic.kind;
      type = prebuilt.type or generic.type;
      carrier = prebuilt.carrier or generic.carrier;
      uplinkRoutes4 = prebuilt.uplinkRoutes4 or generic.uplinkRoutes4 or [ ];
      uplinkRoutes6 = prebuilt.uplinkRoutes6 or generic.uplinkRoutes6 or [ ];
      routes = ifaceRoutes prebuilt;
    };

in
{
  inherit
    canonicalCidr
    ifaceRoutes
    hasPrefixLength
    mkConnectedRoute
    logicalInterfaceNameFor
    overlayInterfaceNameFor
    mkLogicalIface
    mkOverlayIface
    mkIfaceBase
    mergePrebuiltIface
    networksOf
    ;
}
