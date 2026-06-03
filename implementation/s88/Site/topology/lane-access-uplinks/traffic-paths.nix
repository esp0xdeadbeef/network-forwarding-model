{ lib, self ? { outPath = ./.; }, ... }:

let
  trace = import (self.outPath + "/lib/trace.nix") { };
in

{
  uplinksByAccessUnit =
    { site
    , accessUnitNames
    , compilerIndexes
    ,
    }:
    let
      inherit (compilerIndexes)
        accessUnitByTenant
        serviceProviderTenantsByName
        ;

      sourceAccessUnits =
        source:
        let
          kind = source.kind or null;
        in
        if kind == "tenant" then
          let
            tenantName = toString (source.name or "");
            accessUnit = accessUnitByTenant.${tenantName} or null;
          in
          if accessUnit == null then [ ] else [ accessUnit ]
        else if kind == "tenant-set" then
          let
            members = if builtins.isList (source.members or null) then map toString source.members else [ ];
          in
          lib.unique (lib.filter (x: x != null) (map (tenant: accessUnitByTenant.${tenant} or null) members))
        else if kind == "service" then
          let
            serviceName = toString (source.name or "");
            providerTenants = serviceProviderTenantsByName.${serviceName} or [ ];
          in
          lib.unique (lib.filter (x: x != null) (map (tenant: accessUnitByTenant.${tenant} or null) providerTenants))
        else
          [ ];

      pathAccessUnits =
        path:
        lib.filter
          (
            nodeName: builtins.elem nodeName accessUnitNames
          )
          (map toString path);

      pathUplinks =
        path:
        let
          pathSet = builtins.listToAttrs (map
            (nodeName: {
              name = toString nodeName;
              value = true;
            })
            path);
          cores = site.upstreams.cores or { };
          matchingCores = lib.filter (coreName: builtins.hasAttr coreName pathSet) (builtins.attrNames cores);
        in
        lib.concatMap
          (
            coreName:
            map (u: toString (u.name or "")) (cores.${coreName} or [ ])
          )
          matchingCores;

      destinationUplinks =
        destination:
        if (destination.kind or null) != "external" then
          [ ]
        else if builtins.isList (destination.uplinks or null) then
          map toString destination.uplinks
        else if (destination.name or null) != null then
          [ (toString destination.name) ]
        else
          [ ];

      perPath =
        path:
        if !(builtins.isAttrs path) || (path.action or "allow") != "allow" then
          [ ]
        else
          let
            alternatives = path.nodePathAlternatives or [ (path.nodePath or [ ]) ];
            sourceUnits = sourceAccessUnits (path.source or { });
            pathUnits = lib.concatMap pathAccessUnits alternatives;
            accessUnits =
              lib.filter
                (unit: builtins.elem unit accessUnitNames)
                (lib.unique (sourceUnits ++ pathUnits));
            uplinks =
              let
                explicit = destinationUplinks (path.destination or { });
              in
              if explicit != [ ] then explicit else lib.concatMap pathUplinks alternatives;
          in
          lib.concatMap
            (
              accessUnit:
              map
                (uplinkName: {
                  inherit accessUnit uplinkName;
                })
                uplinks
            )
            accessUnits;

      trafficPathEntries = lib.concatMap perPath (site.trafficPaths or [ ]);
    in
    trace.emit "topology:lane-access-uplinks:traffic-paths=${toString (builtins.length (site.trafficPaths or [ ]))}:entries=${toString (builtins.length trafficPathEntries)}" (
      builtins.foldl'
        (
          acc: entry:
          if (entry.accessUnit or "") == "" || (entry.uplinkName or "") == "" then
            acc
          else
            acc // {
              "${entry.accessUnit}" = (acc.${entry.accessUnit} or [ ]) ++ [ entry.uplinkName ];
            }
        )
        { }
        trafficPathEntries
    );
}
