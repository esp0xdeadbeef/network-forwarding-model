{ lib }:

let
  default4 = "0.0.0.0/0";
  default6 = "::/0";

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

  normalizeIntent =
    x:
    if x == null then
      null
    else if builtins.isAttrs x && (x.kind or null) != null then
      x // { kind = toString x.kind; }
    else if builtins.isString x then
      { kind = toString x; }
    else
      { kind = toString x; };

  inferRouteIntent =
    r:
    if r ? intent && r.intent != null then
      normalizeIntent r.intent
    else if
      (r.overlay or null) != null || (r.peerSite or null) != null || (r.proto or null) == "overlay"
    then
      { kind = "overlay-reachability"; }
    else if (r.dst or null) == default4 || (r.dst or null) == default6 then
      { kind = "default-reachability"; }
    else if (r.proto or null) == "connected" then
      { kind = "connected-reachability"; }
    else if (r.proto or null) == "uplink" then
      { kind = "uplink-learned-reachability"; }
    else if (r.proto or null) == "internal" then
      { kind = "internal-reachability"; }
    else
      null;

  annotateRoute =
    r:
    let
      intent = inferRouteIntent r;
    in
    r // lib.optionalAttrs (intent != null) { inherit intent; };

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

  routeIntentKey =
    r:
    let
      intent = inferRouteIntent r;
    in
    if intent == null then "" else toString intent.kind;

  routeForwardingKey =
    r:
    "${toString (r.dst or "")}|${toString (r.via4 or "")}|${toString (r.via6 or "")}|${toString (r.proto or "")}|${routeIntentKey r}|${toString (r.overlay or "")}|${toString (r.peerSite or "")}|${builtins.toJSON (r.lane or null)}|${toString (r.reason or "")}";

  canonicalizeRoute =
    prev0: next0:
    let
      prev = annotateRoute prev0;
      next = annotateRoute next0;

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

      mergedIntent =
        if (chosen.intent or null) != null then
          normalizeIntent chosen.intent
        else if (other.intent or null) != null then
          normalizeIntent other.intent
        else
          inferRouteIntent chosen;

      mergedOverlay = if (chosen.overlay or null) != null then chosen.overlay else other.overlay or null;

      mergedPeerSite =
        if (chosen.peerSite or null) != null then chosen.peerSite else other.peerSite or null;

      mergedLane = if (chosen.lane or null) != null then chosen.lane else other.lane or null;

      mergedReason = if (chosen.reason or null) != null then chosen.reason else other.reason or null;
    in
    chosen
    // lib.optionalAttrs (mergedProto != null) { proto = mergedProto; }
    // lib.optionalAttrs (mergedIntent != null) { intent = mergedIntent; }
    // lib.optionalAttrs (mergedOverlay != null) { overlay = mergedOverlay; }
    // lib.optionalAttrs (mergedPeerSite != null) { peerSite = mergedPeerSite; }
    // lib.optionalAttrs (mergedLane != null) { lane = mergedLane; }
    // lib.optionalAttrs (mergedReason != null) { reason = mergedReason; };

  dedupeRoutes =
    routes0:
    builtins.attrValues (
      builtins.foldl' (
        acc: r0:
        let
          r = annotateRoute r0;
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
  inherit
    normalizeIntent
    inferRouteIntent
    annotateRoute
    routeProtoRank
    routeIntentKey
    routeForwardingKey
    canonicalizeRoute
    dedupeRoutes
    ifaceRoutes
    ;
}
