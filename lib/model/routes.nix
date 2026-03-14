{ lib }:

let
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

  routeProtoRank =
    proto:
    if proto == "connected" then
      500
    else if proto == "uplink" then
      400
    else if proto == "internal" then
      300
    else if proto == "overlay" then
      200
    else if proto == "default" then
      100
    else
      0;

  routeForwardingKey =
    r: "${toString (r.dst or "")}|${toString (r.via4 or "")}|${toString (r.via6 or "")}";

  canonicalizeRoute =
    prev: next:
    let
      prevRank = routeProtoRank (prev.proto or null);
      nextRank = routeProtoRank (next.proto or null);

      chosen = if nextRank > prevRank then next else prev;
      other = if nextRank > prevRank then prev else next;

      mergedProto =
        let
          cp = chosen.proto or null;
          op = other.proto or null;
        in
        if cp != null then cp else op;
    in
    chosen // lib.optionalAttrs (mergedProto != null) { proto = mergedProto; };

  dedupeRoutes =
    routes0:
    builtins.attrValues (
      builtins.foldl' (
        acc: r:
        let
          k = routeForwardingKey r;
        in
        acc
        // {
          "${k}" = if acc ? "${k}" then canonicalizeRoute acc.${k} r else r;
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
  routeProtoRank = routeProtoRank;
  routeForwardingKey = routeForwardingKey;
  canonicalizeRoute = canonicalizeRoute;
  dedupeRoutes = dedupeRoutes;
  ifaceRoutes = ifaceRoutes;
}
