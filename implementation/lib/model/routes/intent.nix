{ ... }:

let
  default4 = "0.0.0.0/0";
  default6 = "::/0";

  normalize =
    x:
    if x == null then
      null
    else if builtins.isAttrs x && (x.kind or null) != null then
      x // { kind = toString x.kind; }
    else if builtins.isString x then
      { kind = toString x; }
    else
      { kind = toString x; };

  infer =
    r:
    if r ? intent && r.intent != null then
      normalize r.intent
    else if (r.overlay or null) != null || (r.peerSite or null) != null || (r.proto or null) == "overlay" then
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

in
{
  inherit normalize infer;
}
