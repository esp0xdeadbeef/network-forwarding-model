{
  lib,
  self ? {
    outPath = ./.;
  },
  ...
}:

let
  trace = import (self.outPath + "/lib/trace.nix") { };
in

{
  uplinksByAccessUnit =
    {
      site,
      accessUnitNames,
      compilerIndexes,
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
          lib.unique (
            lib.filter (x: x != null) (map (tenant: accessUnitByTenant.${tenant} or null) providerTenants)
          )
        else
          [ ];

      pathAccessUnits =
        path: lib.filter (nodeName: builtins.elem nodeName accessUnitNames) (map toString path);

      pathUplinks =
        path:
        let
          pathSet = builtins.listToAttrs (
            map (nodeName: {
              name = toString nodeName;
              value = true;
            }) path
          );
          # FS-322/FS-171: exit surface names are owned by the topology nodes
          # that declare `uplinks`.  Prefer a compiler-emitted
          # `upstreams.cores` mapping, but fall back to the core nodes' own
          # `uplinks` (same shape compiler-indexes uses) so a site that only
          # models node uplinks still yields its per-access selector lanes.
          cores = site.upstreams.cores or { };
          nodes = (site.topology or { }).nodes or { };
          uplinksForCore =
            coreName:
            let
              node = nodes.${coreName} or { };
              nodeUplinks = node.uplinks or { };
            in
            if builtins.isAttrs (cores.${coreName} or null) then
              map (u: toString (u.name or "")) cores.${coreName}
            else if builtins.isAttrs nodeUplinks then
              map (n: toString n) (builtins.attrNames nodeUplinks)
            else
              [ ];
          matchingCores = lib.filter (coreName: builtins.hasAttr coreName pathSet) (
            lib.unique (builtins.attrNames cores ++ builtins.attrNames nodes)
          );
        in
        lib.concatMap (coreName: uplinksForCore coreName) matchingCores;

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

      selectedSurfacesFor =
        unit:
        let
          sel = ((site.topology or { }).nodes or { }).${unit}.selects or [ ];
        in
        lib.unique (
          lib.concatMap (
            entry:
            if !(builtins.isAttrs entry) then
              [ ]
            else
              let
                surf = entry.surface or null;
                sc = entry.scope or null;
              in
              if surf != null then
                [ (toString surf) ]
              else if sc != null then
                [ (toString sc) ]
              else
                [ ]
          ) (if builtins.isList sel then sel else [ ])
        );

      perPath =
        path:
        if !(builtins.isAttrs path) || (path.action or "allow") != "allow" then
          [ ]
        else
          let
            alternatives = path.nodePathAlternatives or [ (path.nodePath or [ ]) ];
            sourceUnits = sourceAccessUnits (path.source or { });
            pathUnits = lib.concatMap pathAccessUnits alternatives;
            accessUnits = lib.filter (unit: builtins.elem unit accessUnitNames) (
              lib.unique (sourceUnits ++ pathUnits)
            );
            explicit = destinationUplinks (path.destination or { });
          in
          lib.concatMap (
            accessUnit:
            let
              # FS-322: reachability is the selecting scope's `selects`. For a
              # bare external destination, use the exit surfaces the access
              # scope selected, not every uplink the core on the path hosts.
              selected = if explicit == [ ] then selectedSurfacesFor accessUnit else [ ];
              uplinks =
                if explicit != [ ] then
                  explicit
                else if selected != [ ] then
                  selected
                else
                  lib.concatMap pathUplinks alternatives;
            in
            map (uplinkName: {
              inherit accessUnit uplinkName;
            }) uplinks
          ) accessUnits;

      trafficPathEntries = lib.concatMap perPath (site.trafficPaths or [ ]);
    in
    trace.emit
      "topology:lane-access-uplinks:traffic-paths=${
        toString (builtins.length (site.trafficPaths or [ ]))
      }:entries=${toString (builtins.length trafficPathEntries)}"
      (
        builtins.foldl' (
          acc: entry:
          if (entry.accessUnit or "") == "" || (entry.uplinkName or "") == "" then
            acc
          else
            acc
            // {
              "${entry.accessUnit}" = (acc.${entry.accessUnit} or [ ]) ++ [ entry.uplinkName ];
            }
        ) { } trafficPathEntries
      );
}
