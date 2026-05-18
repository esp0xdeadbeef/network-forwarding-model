{ lib, self ? { outPath = ./.; }, ... }:

let
  prefix = import (self.outPath + "/implementation/lib/model/prefix-utils.nix") { inherit lib self; };
  inherit (prefix) canonicalCidr mkConnectedRoute;

in
{
  nameFor = netName: "tenant-${toString netName}";

  build =
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
      logical = true;
      virtual = true;
      l2 = false;
      kind = net.kind or "tenant";
      type = "logical";
      carrier = "logical";
      tenant = tenantName;
      network = { name = tenantName; kind = net.kind or "tenant"; ipv4 = subnet4; ipv6 = subnet6; };
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
      ra6Prefixes = map canonicalCidr (net.ra6Prefixes or [ ]);
      acceptRA = false;
      dhcp = false;
    };
}
