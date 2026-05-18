{ lib, self ? { outPath = ./.; }, ... }:

let
  addr = import (self.outPath + "/implementation/lib/model/addressing.nix") { inherit lib self; };
  common = import (self.outPath + "/implementation/s88/Site/topology/common.nix") { inherit lib self; };
  pools = import (self.outPath + "/implementation/s88/Site/topology/pools.nix") { inherit lib self; };
  tenants = import (self.outPath + "/implementation/s88/Site/topology/tenants.nix") { inherit lib self; };

in
{
  build =
    {
      site,
      siteForTopology,
      unitNames,
      localPool,
      rolesResult,
    }:
    let
      explicitLoopbackByUnit = builtins.listToAttrs (
        map (unitName: {
          name = unitName;
          value = pools.explicitLoopbackFromSite site unitName;
        }) unitNames
      );
    in
    lib.listToAttrs (
      lib.imap0 (idx: rawUnitName: {
        name = toString rawUnitName;
        value =
          let
            unitName = toString rawUnitName;
            base = common.nodeFromSite site unitName;
            attachedNetworks = tenants.tenantNetworksForUnit siteForTopology unitName;
            explicitLoopback = explicitLoopbackByUnit.${unitName} or null;

            alloc4 =
              if localPool != null && (localPool.ipv4 or null) != null then
                addr.hostCidr idx "${common.stripMask localPool.ipv4}/32"
              else
                null;

            alloc6 =
              if localPool != null && (localPool.ipv6 or null) != null then
                addr.hostCidr idx "${common.stripMask localPool.ipv6}/128"
              else
                null;

            final4 =
              if explicitLoopback != null && (explicitLoopback.ipv4 or null) != null then explicitLoopback.ipv4 else alloc4;
            final6 =
              if explicitLoopback != null && (explicitLoopback.ipv6 or null) != null then explicitLoopback.ipv6 else alloc6;
            loopback = if final4 == null && final6 == null then null else { ipv4 = final4; ipv6 = final6; };
          in
          (builtins.removeAttrs base [ "containers" ])
          // {
            role = rolesResult.roleFromInput unitName;
          }
          // lib.optionalAttrs (attachedNetworks != { }) { networks = attachedNetworks; }
          // lib.optionalAttrs (loopback != null) { inherit loopback; };
      }) unitNames
    );
}
