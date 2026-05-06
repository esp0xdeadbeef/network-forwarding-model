{ lib, self ? { outPath = ./.; }, ... }:

let
  ip = import (self.outPath + "/lib/net/ip-utils.nix") { inherit lib self; };
  prefix = import (self.outPath + "/lib/model/prefix-utils.nix") { inherit lib self; };
  routes = import (self.outPath + "/lib/model/routes.nix") { inherit lib self; };
  logical = import (self.outPath + "/implementation/lib/topology/resolve-helpers/logical-interface.nix") {
    inherit lib self;
  };
  overlay = import (self.outPath + "/implementation/lib/topology/resolve-helpers/overlay-interface.nix") {
    inherit lib self;
  };

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

  logicalInterfaceNameFor = logical.nameFor;
  overlayInterfaceNameFor = overlay.nameFor;
  mkLogicalIface = logical.build;
  mkOverlayIface = overlay.build;

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

      interfaceName = if (ep.interface or null) != null then toString ep.interface else toString linkName;
    in
    {
      name = interfaceName;
      interface = interfaceName;
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
      name = prebuilt.name or generic.name;
      interface = prebuilt.interface or generic.interface;
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
