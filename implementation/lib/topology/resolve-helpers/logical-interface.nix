{ lib, self ? { outPath = ./.; }, ... }:

let
  addressing = import (self.outPath + "/implementation/lib/model/addressing.nix") { inherit lib self; };
  prefix = import (self.outPath + "/implementation/lib/model/prefix-utils.nix") { inherit lib self; };
  inherit (prefix) canonicalCidr mkConnectedRoute;

in
{
  nameFor = netName: "tenant-${toString netName}";

  build =
    { nodeName
    , nodeRole ? null
    , ifName
    , netName
    , net
    ,
    }:
    let
      subnet4 = if net ? ipv4 && net.ipv4 != null then canonicalCidr net.ipv4 else null;
      subnet6 = if net ? ipv6 && net.ipv6 != null then canonicalCidr net.ipv6 else null;
      isGatewayAttachment = nodeRole == "access" && (net.gateway or true) != false;
      addr4 = if isGatewayAttachment && subnet4 != null then addressing.hostCidr 1 subnet4 else null;
      addr6 = if isGatewayAttachment && subnet6 != null then addressing.hostCidr 1 subnet6 else null;
      tenantName = if net ? name && net.name != null then toString net.name else toString netName;
    in
    {
      name = ifName;
      node = nodeName;
      interface = ifName;
      logical = true;
      virtual = true;
      l2 = false;
      kind = net.kind or "tenant";
      type = "logical";
      carrier = "logical";
      tenant = tenantName;
      network =
        { name = tenantName; kind = net.kind or "tenant"; ipv4 = subnet4; ipv6 = subnet6; }
        // lib.optionalAttrs ((net.publicIpv4 or null) != null) { publicIpv4 = net.publicIpv4; };
      gateway = false;
      addr4 = addr4;
      peerAddr4 = null;
      addr6 = addr6;
      peerAddr6 = null;
      addr6Public = null;
      subnet4 = subnet4;
      subnet6 = subnet6;
      ll6 = null;
      uplink = null;
      upstream = null;
      overlay = null;
      routes = {
        ipv4 = lib.optional (isGatewayAttachment && subnet4 != null) (mkConnectedRoute subnet4);
        ipv6 = lib.optional (isGatewayAttachment && subnet6 != null) (mkConnectedRoute subnet6);
      };
      ra6Prefixes = map canonicalCidr (net.ra6Prefixes or [ ]);
      routedPrefixes = net.routedPrefixes or [ ];
      acceptRA = !isGatewayAttachment && subnet6 != null;
      dhcp = !isGatewayAttachment && subnet4 != null;
    };
}
