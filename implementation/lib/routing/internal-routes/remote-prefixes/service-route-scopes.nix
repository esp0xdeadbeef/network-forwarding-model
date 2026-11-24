{ lib, self ? { outPath = ./.; }, ... }:

let
  cleanName = value: if value == null then "" else toString value;

  siteResolverPaths = import (self.outPath + "/implementation/lib/routing/site-resolver-paths.nix") {
    inherit lib;
  };

  asList =
    value:
    if value == null then [ ] else if builtins.isList value then value else [ value ];

in
{
  build =
    { nodes
    , topo
    ,
    }:
    let
      # FS-540 / FS-260: the forwarding model owns the resolver path. It is
      # published on the site as `resolverPaths`; the route scopes use the
      # concrete node sequence from there, so the scoped route follows the
      # canonical stages instead of a physical shortest path.
      resolverPaths = siteResolverPaths.resolverPaths topo;

      accessUnitByTenant =
        builtins.foldl'
          (
            acc: attachment:
              if !(builtins.isAttrs attachment) || (attachment.kind or null) != "tenant" then
                acc
              else
                let
                  tenantName = cleanName (attachment.name or null);
                  unitName = cleanName (attachment.unit or null);
                in
                if tenantName == "" || unitName == "" then acc else acc // { "${tenantName}" = unitName; }
          )
          { }
          (topo.attachments or [ ]);

      endpointTenantByName =
        builtins.foldl'
          (
            acc: endpoint:
              if !(builtins.isAttrs endpoint) then
                acc
              else
                let
                  endpointName = cleanName (endpoint.name or null);
                  tenantName = cleanName (endpoint.tenant or null);
                in
                if endpointName == "" || tenantName == "" then acc else acc // { "${endpointName}" = tenantName; }
          )
          { }
          (topo.ownership.endpoints or [ ]);

      serviceProviderAccessUnits =
        serviceName:
        let
          services =
            if (topo.communicationContract or { }) ? services then
              topo.communicationContract.services
            else
              topo.services or [ ];
          matches =
            lib.filter
              (service: builtins.isAttrs service && cleanName (service.name or null) == serviceName)
              services;
          providers = lib.concatMap
            (service: map (provider: cleanName provider) (asList (service.providers or [ ])))
            matches;
        in
        lib.unique (
          lib.filter (unitName: unitName != "") (
            map
              (
                provider:
                let
                  tenantName = endpointTenantByName.${provider} or "";
                in
                if tenantName == "" then "" else accessUnitByTenant.${tenantName} or ""
              )
              providers
          )
        );

      sourceExternalUplinks =
        source:
        if (source.kind or null) != "external" then
          [ ]
        else if builtins.isList (source.uplinks or null) then
          map (uplink: cleanName uplink) source.uplinks
        else if (source.name or null) != null then
          [ (cleanName source.name) ]
        else
          [ ];

      accessUnitsInPath =
        path:
        lib.unique (
          lib.filter
            (nodeName: ((nodes.${nodeName} or { }).role or null) == "access")
            (map (nodeName: cleanName nodeName) path)
        );

      dnsServiceRouteScopes =
        path:
        if
          !(builtins.isAttrs path)
          || (path.action or null) != "allow"
          || (path.trafficType or null) != "dns"
          || ((path.destination or { }).kind or null) != "service"
        then
          [ ]
        else
          let
            serviceName = cleanName ((path.destination or { }).name or null);
            providerAccessUnits = serviceProviderAccessUnits serviceName;
            uplinks = sourceExternalUplinks (path.source or { });
            resolverPath = lib.findFirst
              (
                record:
                (record.relationId or null) == (path.relationId or null)
                && (record.pathNodes or [ ]) != [ ]
              )
              null
              resolverPaths;
            alternatives =
              if resolverPath != null then
                [ resolverPath.pathNodes ]
              else
                path.nodePathAlternatives or [ (path.nodePath or [ ]) ];
            policyNode = if resolverPath != null then resolverPath.policyPoint else null;
            requesterAccessUnits =
              lib.filter
                (accessUnit: !(builtins.elem accessUnit providerAccessUnits))
                (lib.concatMap accessUnitsInPath alternatives);
          in
          if serviceName == "" || providerAccessUnits == [ ] || requesterAccessUnits == [ ] then
            [ ]
          else
            let
              # FS-540-HDS-010-SDS-010-SMS-040: the requester's reachability to the
              # resolver is keyed by the requester's own lane. An uplink is a
              # refinement that only exists when the relation declares one
              # (an `external` source); a tenant-set requester has no such
              # declaration, and requiring one emitted nothing at all -- the
              # resolver was unreachable from every requester lane. Emit the
              # lane scope, narrowed to the declared uplinks when they exist.
              scopedUplinks = if uplinks == [ ] then [ null ] else uplinks;
            in
            lib.concatMap
              (
                owner:
                lib.concatMap
                  (
                    access:
                    map
                      (uplink: {
                        inherit access owner serviceName;
                        # FS-260-HDS-010-SDS-010-SMS-050: the compiled traffic path is the
                        # traversal authority. Carry its node sequence so the
                        # route resolver takes the staged next hop (policy on
                        # the upward leg, the destination lane on the downward
                        # leg) instead of a physical shortest path that skips a
                        # stage.
                        nodePaths = alternatives;
                        inherit policyNode;
                      } // lib.optionalAttrs (uplink != null) { inherit uplink; })
                      scopedUplinks
                  )
                  requesterAccessUnits
              )
              providerAccessUnits;
    in
    builtins.foldl'
      (
        acc: scope:
        acc // {
          "${scope.owner}" = lib.unique (
            (acc.${scope.owner} or [ ])
            ++ [
              (builtins.removeAttrs scope [ "owner" ])
            ]
          );
        }
      )
      { }
      (lib.concatMap dnsServiceRouteScopes (topo.trafficPaths or [ ]));
}
