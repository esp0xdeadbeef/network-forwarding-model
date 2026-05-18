{ lib, self ? { outPath = ./.; }, ... }:

let
  prefix = import (self.outPath + "/implementation/lib/model/prefix-utils.nix") { inherit lib self; };
  routes = import (self.outPath + "/implementation/lib/model/routes.nix") { inherit lib self; };

  mkConnectedRoute = prefix.mkConnectedRoute;
  normalizeRouteList = routes.normalizeRouteDestinationList;

  tenantFromUplink =
    uplink:
    if
      uplink ? ingressSubject
      && uplink.ingressSubject ? kind
      && uplink.ingressSubject.kind == "tenant"
      && uplink.ingressSubject ? name
      && uplink.ingressSubject.name != null
    then
      uplink.ingressSubject.name
    else
      "unclassified";

  mkInterface =
    {
      linkName,
      uplinkName,
      tenant,
      uplink,
    }:
    {
      name = linkName;
      interface = linkName;
      link = linkName;
      kind = "wan";
      type = "wan";
      carrier = "wan";
      uplink = uplinkName;
      upstream = uplinkName;
      overlay = null;

      tenant = tenant;
      gateway = true;

      addr4 = uplink.addr4 or null;
      peerAddr4 = uplink.peerAddr4 or null;
      addr6 = uplink.addr6 or null;
      peerAddr6 = uplink.peerAddr6 or null;
      addr6Public = null;
      ll6 = uplink.ll6 or null;

      uplinkRoutes4 = normalizeRouteList (uplink.ipv4 or [ ]);
      uplinkRoutes6 = normalizeRouteList (uplink.ipv6 or [ ]);

      routes = {
        ipv4 = lib.optional ((uplink.addr4 or null) != null) (mkConnectedRoute uplink.addr4);
        ipv6 = lib.optional ((uplink.addr6 or null) != null) (mkConnectedRoute uplink.addr6);
      };

      ra6Prefixes = [ ];
      acceptRA = false;
      dhcp = false;
    };

  mkLink =
    _idx: spec:
    let
      unitName = spec.unitName;
      uplink = spec.uplink;
      uplinkName = uplink.name;
      linkName = "wan-${unitName}-${uplinkName}";
      tenant = tenantFromUplink uplink;

      interfaceData = mkInterface {
        inherit
          linkName
          uplinkName
          tenant
          uplink
          ;
      };
    in
    {
      name = linkName;
      value = {
        kind = "wan";
        type = "wan";
        carrier = "wan";
        uplink = uplinkName;
        upstream = uplinkName;
        overlay = null;
        members = [ unitName ];
        endpoints = {
          "${unitName}" = {
            node = unitName;
            interface = linkName;
            uplink = uplinkName;
            gateway = true;
            tenant = tenant;
            addr4 = uplink.addr4 or null;
            peerAddr4 = uplink.peerAddr4 or null;
            addr6 = uplink.addr6 or null;
            peerAddr6 = uplink.peerAddr6 or null;
            ll6 = uplink.ll6 or null;
            uplinkRoutes4 = normalizeRouteList (uplink.ipv4 or [ ]);
            uplinkRoutes6 = normalizeRouteList (uplink.ipv6 or [ ]);
            inherit interfaceData;
          };
        };
      };
    };

in
{
  build = specs: lib.listToAttrs (lib.imap0 mkLink specs);
}
