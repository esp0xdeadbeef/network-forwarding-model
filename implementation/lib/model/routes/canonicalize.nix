{ lib, intent }:

let
  protoRank =
    proto:
    if proto == "connected" then 500
    else if proto == "uplink" then 400
    else if proto == "internal" then 300
    else if proto == "overlay" then 200
    else if proto == "default" then 100
    else 0;

  annotate =
    r:
    let routeIntent = intent.infer r;
    in r // lib.optionalAttrs (routeIntent != null) { intent = routeIntent; };

  intentKey =
    r:
    let routeIntent = intent.infer r;
    in if routeIntent == null then "" else toString routeIntent.kind;

  forwardingKey =
    r:
    "${toString (r.dst or "")}|${toString (r.via4 or "")}|${toString (r.via6 or "")}|${toString (r.proto or "")}|${intentKey r}|${toString (r.overlay or "")}|${toString (r.peerSite or "")}|${builtins.toJSON (r.lane or null)}|${toString (r.reason or "")}";

  canonicalize =
    prev0: next0:
    let
      prev = annotate prev0;
      next = annotate next0;
      chosen = if protoRank (next.proto or null) > protoRank (prev.proto or null) then next else prev;
      other = if chosen == next then prev else next;
      mergedIntent =
        if (chosen.intent or null) != null then intent.normalize chosen.intent
        else if (other.intent or null) != null then intent.normalize other.intent
        else intent.infer chosen;
    in
    chosen
    // lib.optionalAttrs ((chosen.proto or null) != null || (other.proto or null) != null) {
      proto = if (chosen.proto or null) != null then chosen.proto else other.proto;
    }
    // lib.optionalAttrs (mergedIntent != null) { intent = mergedIntent; }
    // lib.optionalAttrs ((chosen.overlay or other.overlay or null) != null) {
      overlay = if (chosen.overlay or null) != null then chosen.overlay else other.overlay;
    }
    // lib.optionalAttrs ((chosen.peerSite or other.peerSite or null) != null) {
      peerSite = if (chosen.peerSite or null) != null then chosen.peerSite else other.peerSite;
    }
    // lib.optionalAttrs ((chosen.lane or other.lane or null) != null) {
      lane = if (chosen.lane or null) != null then chosen.lane else other.lane;
    }
    // lib.optionalAttrs ((chosen.reason or other.reason or null) != null) {
      reason = if (chosen.reason or null) != null then chosen.reason else other.reason;
    };

in
{
  inherit
    annotate
    canonicalize
    forwardingKey
    intentKey
    protoRank
    ;
}
