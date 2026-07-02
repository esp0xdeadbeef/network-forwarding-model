{ lib, self ? { outPath = ./.; }, ... }:

let
  helpers = import (self.outPath + "/implementation/lib/routing/static-helpers.nix") { inherit lib self; };

  sortedUnique = xs: lib.sort (a: b: toString a < toString b) (lib.unique (map toString xs));
  ifaceRoutes = iface: let routes = iface.routes or { }; in (routes.ipv4 or [ ]) ++ (routes.ipv6 or [ ]) ++ (iface.routes4 or [ ]) ++ (iface.routes6 or [ ]);
  isDefault = route: (route.dst or null) == helpers.default4 || (route.dst or null) == helpers.default6;

  tenantsForAccess =
    topo: accessName:
    sortedUnique (
      lib.filter (tenant: tenant != null) (
        map
          (
            attachment:
            if
              (attachment.kind or null) == "tenant"
              && (attachment.unit or null) != null
              && toString attachment.unit == accessName
            then
              attachment.name or null
            else
              null
          )
          (topo.attachments or [ ])
      )
    );

  tenantPrefixOwnerByDst =
    topo:
    let
      tenantAccessEntries =
        lib.concatMap
          (
            accessName:
            map (tenantName: { inherit accessName tenantName; }) (tenantsForAccess topo accessName)
          )
          (builtins.attrNames (topo.nodes or { }));
      accessForTenant = builtins.listToAttrs (
        map (entry: { name = entry.tenantName; value = entry.accessName; }) tenantAccessEntries
      );
    in
    builtins.listToAttrs (
      lib.concatMap
        (
          tenant:
          if
            builtins.isAttrs tenant
            && (tenant.name or null) != null
            && (tenant.ipv4 or null) != null
            && builtins.hasAttr (toString tenant.name) accessForTenant
          then
            [
              {
                name = helpers.canonicalCidr tenant.ipv4;
                value = accessForTenant.${toString tenant.name};
              }
            ]
          else
            [ ]
        )
        ((topo.domains or { }).tenants or [ ])
    );

  policyRoutes =
    topo:
    lib.concatMap
      (
        nodeName:
        let node = (topo.nodes or { }).${nodeName};
        in
        lib.concatMap
          (
            ifName:
            map
              (route: {
                inherit ifName nodeName route;
                laneKey = "${toString route.lane.access}|${toString route.lane.uplink}";
              })
              (
                lib.filter
                  (route:
                    (route.policyOnly or false)
                    && (route.direction or null) != "outbound"
                    && (route.lane.access or null) != null
                    && (route.lane.uplink or null) != null)
                  (ifaceRoutes ((node.interfaces or { }).${ifName} or { }))
              )
          )
          (builtins.attrNames (node.interfaces or { }))
      )
      (builtins.attrNames (topo.nodes or { }));

  sharedLaneSetFor =
    routes: item:
    sortedUnique (
      map
        (candidate: candidate.laneKey)
        (lib.filter (candidate: candidate.nodeName == item.nodeName && candidate.ifName == item.ifName) routes)
    );

in
{
  validate =
    topo:
    let
      routes = policyRoutes topo;
      ownerByDst = tenantPrefixOwnerByDst topo;
      isShared = item: builtins.length (sharedLaneSetFor routes item) > 1;
      sharedRoutes = lib.filter isShared routes;

      defaultCatchalls = lib.filter (item: isDefault item.route) sharedRoutes;
      firstDefault = if defaultCatchalls == [ ] then null else builtins.head defaultCatchalls;

      inversions = lib.filter
        (
          item:
          let owner = ownerByDst.${item.route.dst or ""} or null;
          in owner != null && owner != (item.route.lane.access or null)
        )
        sharedRoutes;
      firstInversion = if inversions == [ ] then null else builtins.head inversions;
      inversionOwner =
        if firstInversion == null then null else ownerByDst.${firstInversion.route.dst or ""} or null;
    in
    if firstDefault != null then
      throw ''
        network-forwarding-model: diagnostic.default-route-catch-all-shared-interface

        node: ${firstDefault.nodeName}
        interface: ${firstDefault.ifName}
        lane: ${firstDefault.laneKey}
        route: ${builtins.toJSON firstDefault.route}
        expected: shared source interfaces must not carry policyOnly default-route catch-alls
      ''
    else if firstInversion != null then
      throw ''
        network-forwarding-model: diagnostic.priority-inversion-route-capture

        node: ${firstInversion.nodeName}
        interface: ${firstInversion.ifName}
        capturingLane: ${firstInversion.laneKey}
        capturedSubnet: ${firstInversion.route.dst}
        correctAccess: ${inversionOwner}
        route: ${builtins.toJSON firstInversion.route}
      ''
    else
      true;
}
