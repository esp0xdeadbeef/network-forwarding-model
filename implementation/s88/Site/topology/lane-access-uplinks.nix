{ lib, self ? { outPath = ./.; }, ... }:

let
  trafficPaths = import ./lane-access-uplinks/traffic-paths.nix { inherit lib self; };
in

{
  derive =
    {
      site,
      accessUnitNames,
      compilerIndexes,
    }:
    let
      inherit (compilerIndexes)
        allUplinkNames
        serviceProviderTenantsByName
        tenantsByAccessUnit
        ;

      serviceProviderTenants =
        serviceName: serviceProviderTenantsByName.${serviceName} or [ ];

      relationToUplinkNames =
        rel:
        let
          to = rel.to or { };
          kind = to.kind or null;
          uplinks = to.uplinks or null;
          name = to.name or null;
        in
        if kind != "external" then
          [ ]
        else if builtins.isList uplinks then
          map toString uplinks
        else if name != null && toString name != "" then
          [ (toString name) ]
        else
          [ ];

      trafficPathUplinksByAccessUnit =
        trafficPaths.uplinksByAccessUnit {
          inherit
            compilerIndexes
            site
            accessUnitNames
            ;
        };

      relationAppliesToAccessUnit =
        unit: rel:
        let
          from = rel.from or { };
          unitTenants = tenantsByAccessUnit.${unit} or [ ];
          kind = from.kind or null;
        in
        if kind == "tenant" then
          builtins.elem (toString (from.name or "")) unitTenants
        else if kind == "tenant-set" then
          let
            members = if builtins.isList (from.members or null) then map toString from.members else [ ];
          in
          lib.any (t: builtins.elem t members) unitTenants
        else if kind == "service" then
          let
            providerTenants = serviceProviderTenants (toString (from.name or ""));
          in
          lib.any (tenant: builtins.elem tenant unitTenants) providerTenants
        else
          false;

      allowedUplinksFor =
        unit:
        let
          relations = site.communicationContract.allowedRelations or [ ];
          hasAnyAllowRelation = lib.any (rel: (rel.action or null) == "allow") relations;
          compilerUplinks = trafficPathUplinksByAccessUnit.${unit} or [ ];
          uplinks =
            if compilerUplinks != [ ] then
              compilerUplinks
            else if !hasAnyAllowRelation then
              allUplinkNames
            else
              lib.concatMap (
                rel:
                if (rel.action or null) == "allow" && relationAppliesToAccessUnit unit rel then
                  relationToUplinkNames rel
                else
                  [ ]
              ) relations;
        in
        lib.sort (a: b: a < b) (lib.unique (lib.filter (s: s != "") (map toString uplinks)));
    in
    builtins.listToAttrs (
      map (unit: {
        name = unit;
        value = allowedUplinksFor unit;
      }) accessUnitNames
    );
}
