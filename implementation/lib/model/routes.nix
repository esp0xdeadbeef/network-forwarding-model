{ lib, self ? { outPath = ./.; }, ... }:

let
  intent = import (self.outPath + "/implementation/lib/model/routes/intent.nix") { inherit lib self; };
  canonical = import (self.outPath + "/implementation/lib/model/routes/canonicalize.nix") {
    inherit lib intent;
  };

  ifaceRoutesRaw =
    iface:
    if iface ? routes && builtins.isAttrs iface.routes then
      {
        ipv4 = iface.routes.ipv4 or [ ];
        ipv6 = iface.routes.ipv6 or [ ];
      }
    else
      {
        ipv4 = iface.routes4 or [ ];
        ipv6 = iface.routes6 or [ ];
      };

  normalizeRouteEntry =
    x:
    if builtins.isString x then
      { dst = toString x; }
    else if builtins.isAttrs x then
      (builtins.removeAttrs x [ "preserveDst" ])
      // lib.optionalAttrs ((x.dst or null) != null) { dst = toString x.dst; }
    else
      { dst = toString x; };

  normalizeRouteList =
    xs:
    let
      normalized =
        if xs == null then
          [ ]
        else if builtins.isList xs then
          map normalizeRouteEntry xs
        else
          [ (normalizeRouteEntry xs) ];
    in
    dedupeRoutes normalized;

  normalizeRouteDestination =
    x:
    if builtins.isString x then
      toString x
    else if builtins.isAttrs x && (x.dst or null) != null then
      toString x.dst
    else
      toString x;

  normalizeRouteDestinationList =
    xs:
    if xs == null then
      [ ]
    else if builtins.isList xs then
      map normalizeRouteDestination xs
    else
      [ (normalizeRouteDestination xs) ];

  dedupeRoutes =
    routes0:
    builtins.attrValues (
      builtins.foldl' (
        acc: r0:
        let
          r = canonical.annotate r0;
          k = canonical.forwardingKey r;
        in
        acc
        // {
          "${k}" = if acc ? "${k}" then canonical.canonicalize acc.${k} r else r;
        }
      ) { } routes0
    );

  ifaceRoutes =
    iface:
    let
      raw = ifaceRoutesRaw iface;
    in
    {
      ipv4 = dedupeRoutes raw.ipv4;
      ipv6 = dedupeRoutes raw.ipv6;
    };

in
{
  inherit
    normalizeRouteEntry
    normalizeRouteList
    normalizeRouteDestination
    normalizeRouteDestinationList
    dedupeRoutes
    ifaceRoutes
    ;
  normalizeIntent = intent.normalize;
  inferRouteIntent = intent.infer;
  annotateRoute = canonical.annotate;
  routeProtoRank = canonical.protoRank;
  routeIntentKey = canonical.intentKey;
  routeForwardingKey = canonical.forwardingKey;
  canonicalizeRoute = canonical.canonicalize;
}
