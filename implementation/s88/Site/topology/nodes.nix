{ lib, self ? { outPath = ./.; }, ... }:

let
  addr = import (self.outPath + "/implementation/lib/model/addressing.nix") { inherit lib self; };
  common = import (self.outPath + "/implementation/s88/Site/topology/common.nix") { inherit lib self; };
  pools = import (self.outPath + "/implementation/s88/Site/topology/pools.nix") { inherit lib self; };
  tenants = import (self.outPath + "/implementation/s88/Site/topology/tenants.nix") { inherit lib self; };

in
{
  build =
    { site
    , siteForTopology
    , unitNames
    , localPool
    , rolesResult
    , tenantContext ? tenants.siteContext siteForTopology
    ,
    }:
    let
      explicitLoopbackByUnit = builtins.listToAttrs (
        map
          (unitName: {
            name = unitName;
            value = pools.explicitLoopbackFromSite site unitName;
          })
          unitNames
      );
      contract = site.communicationContract or { };
      hasDnsIntent =
        builtins.any (service: builtins.isAttrs service && (service.trafficType or null) == "dns")
          (contract.services or site.services or [ ])
        || builtins.any (trafficType: builtins.isAttrs trafficType && (trafficType.name or null) == "dns")
          (contract.trafficTypes or [ ]);
      schemaCoreNodeNames = lib.unique (
        builtins.attrNames (site.upstreams.cores or { })
        ++ builtins.attrNames (site.uplinks.cores or { })
        ++ map toString (site.coreNodeNames or [ ])
        ++ map toString (site.forwardingSemantics.coreNodeNames or [ ])
      );
      dnsServiceForRole =
        unitName: role:
        if hasDnsIntent && (role == "access" || role == "core" || builtins.elem unitName schemaCoreNodeNames) then
          { dns = { }; }
        else
          { };
    in
    lib.listToAttrs (
      lib.imap0
        (idx: rawUnitName: {
          name = toString rawUnitName;
          value =
            let
              unitName = toString rawUnitName;
              base = common.nodeFromSite site unitName;
              attachedNetworks = tenants.tenantNetworksForUnitWithContext tenantContext unitName;
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
              role = rolesResult.roleFromInput unitName;
              baseServices = if builtins.isAttrs (base.services or null) then base.services else { };
              services = baseServices // dnsServiceForRole unitName role;
            in
            (builtins.removeAttrs base [ "containers" ])
            // {
              inherit role;
            }
            // lib.optionalAttrs (attachedNetworks != { }) { networks = attachedNetworks; }
            // lib.optionalAttrs (loopback != null) { inherit loopback; }
            // lib.optionalAttrs (services != { }) { inherit services; };
        })
        unitNames
    );
}
