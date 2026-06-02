{ canonicalCidr
, dedupeDynamicRoutes
, lib
, rawDedupeRoutes
, routeUsesDynamicSource
, stripMask
, summarizeCidrs
, trace
,
}:

let
  routeBase =
    r:
    builtins.removeAttrs r [
      "dst"
      "preserveDst"
    ];

  sortRoutesByJSON =
    rs:
    map
      (entry: entry.route)
      (builtins.sort (a: b: a.key < b.key) (
        map
          (route: {
            key = builtins.toJSON route;
            inherit route;
          })
          rs
      ));

  uniqueStrings =
    xs:
    builtins.attrNames (builtins.listToAttrs (map (x: {
      name = x;
      value = true;
    }) xs));

  detectRouteFamily = r: if lib.hasInfix ":" (stripMask r.dst) then 6 else 4;

  routePreservesDst = r: (r.preserveDst or false) == true;

  normalizeStaticRoutes =
    family: staticRoutes:
    if staticRoutes == [ ] then
      [ ]
    else if builtins.length staticRoutes == 1 then
      let
        route = builtins.head (rawDedupeRoutes staticRoutes);
        dst = if routePreservesDst route then route.dst else canonicalCidr route.dst;
      in
      [ (routeBase route // { inherit dst; }) ]
    else
      let
        keyedRoutes = map
          (
            r:
            let
              base = routeBase r;
            in
            {
              inherit base;
              key = builtins.toJSON base;
              preserveDst = routePreservesDst r;
              rawDst = r.dst;
            }
          )
          staticRoutes;
        grouped = builtins.groupBy (r: r.key) keyedRoutes;

        normalizedGroups = builtins.concatMap
          (
            key:
            let
              group = grouped.${key};
              base = (builtins.head group).base;
              preservesDst = builtins.any (r: r.preserveDst) group;
              cidrs =
                if preservesDst then
                  uniqueStrings (map (r: r.rawDst) group)
                else
                  uniqueStrings (map (r: canonicalCidr r.rawDst) group);
              renderedCidrs =
                if preservesDst then
                  builtins.sort (a: b: a < b) cidrs
                else if
                  builtins.length cidrs <= 1
                  && !(family == 6 && builtins.match ".*/0" (builtins.head cidrs) != null)
                then
                  cidrs
                else
                  summarizeCidrs family cidrs;
            in
            map (dst: base // { dst = dst; }) renderedCidrs
          )
          (builtins.attrNames grouped);
      in
      sortRoutesByJSON normalizedGroups;

  normalizeRouteList =
    family: rs:
    trace.emit "routing:normalizeRouteList:${toString family}:${toString (builtins.length rs)}" (
      let
        dynamicRoutes = dedupeDynamicRoutes (builtins.filter routeUsesDynamicSource rs);
        staticRoutes = builtins.filter (r: !(routeUsesDynamicSource r)) rs;
      in
      normalizeStaticRoutes family staticRoutes ++ dynamicRoutes
    );

  dedupeRoutes =
    rs:
    let
      grouped = builtins.groupBy (r: toString (detectRouteFamily r)) rs;
      v4 = if grouped ? "4" then normalizeRouteList 4 grouped."4" else [ ];
      v6 = if grouped ? "6" then normalizeRouteList 6 grouped."6" else [ ];
    in
    sortRoutesByJSON (v4 ++ v6);

in
{
  inherit normalizeRouteList dedupeRoutes sortRoutesByJSON;
}
