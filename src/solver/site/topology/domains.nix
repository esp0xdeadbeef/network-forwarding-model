{ lib }:

let
  normalizeExternalDomainEntry =
    x:
    if builtins.isString x then
      {
        name = toString x;
        kind = "external";
      }
    else if builtins.isAttrs x && (x.name or null) != null then
      x
      // {
        name = toString x.name;
        kind = x.kind or "external";
      }
    else
      null;

  externalDomainsListFrom =
    externals:
    if builtins.isList externals then
      lib.filter (x: x != null) (map normalizeExternalDomainEntry externals)
    else if builtins.isAttrs externals then
      lib.mapAttrsToList (
        name: v:
        let
          normalized = normalizeExternalDomainEntry (v // { inherit name; });
        in
        if normalized == null then
          {
            name = toString name;
            kind = "external";
          }
        else
          normalized
      ) externals
    else
      [ ];

  externalRefNamesFromContract =
    x:
    if builtins.isList x then
      lib.unique (lib.concatMap externalRefNamesFromContract x)
    else if builtins.isAttrs x then
      let
        self =
          if (x.kind or null) == "external" && (x.name or null) != null then [ (toString x.name) ] else [ ];
      in
      lib.unique (self ++ lib.concatMap externalRefNamesFromContract (builtins.attrValues x))
    else
      [ ];

  overlayNamesFromTransport =
    transport:
    if !(builtins.isAttrs transport) then
      [ ]
    else
      let
        overlays = transport.overlays or [ ];
      in
      if builtins.isList overlays then
        lib.unique (
          lib.concatMap (
            overlay:
            if builtins.isString overlay then
              [ (toString overlay) ]
            else if builtins.isAttrs overlay && (overlay.name or null) != null then
              [ (toString overlay.name) ]
            else
              [ ]
          ) overlays
        )
      else if builtins.isAttrs overlays then
        lib.sort (a: b: a < b) (builtins.attrNames overlays)
      else
        [ ];

  mergeExternalDomains =
    existing: names:
    let
      existingList = externalDomainsListFrom existing;
      existingByName = builtins.listToAttrs (
        map (entry: {
          name = entry.name;
          value = entry;
        }) existingList
      );

      addedByName = builtins.listToAttrs (
        map (name: {
          name = toString name;
          value = {
            name = toString name;
            kind = "external";
          };
        }) (lib.filter (name: name != null && name != "") names)
      );
    in
    builtins.attrValues (existingByName // addedByName);

  materializeSiteDomains =
    site:
    let
      domains0 = site.domains or { };
      requiredExternalNames = lib.unique (
        (overlayNamesFromTransport (site.transport or { }))
        ++ (externalRefNamesFromContract (site.communicationContract or { }))
      );
      externals0 = domains0.externals or [ ];
      externals1 = mergeExternalDomains externals0 requiredExternalNames;
    in
    domains0
    // {
      externals = externals1;
    };

in
{
  inherit
    normalizeExternalDomainEntry
    externalDomainsListFrom
    externalRefNamesFromContract
    overlayNamesFromTransport
    mergeExternalDomains
    materializeSiteDomains
    ;
}
