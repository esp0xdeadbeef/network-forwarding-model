{ lib, default6, canonicalCidr }:

let
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
in
{
  mkRoute4 =
    {
      dst,
      via4,
      proto,
      intent ? null,
      extra ? { },
      routeExtra ? { },
    }:
    {
      dst = canonicalCidr dst;
      inherit via4 proto;
    }
    // lib.optionalAttrs (normalizeIntent intent != null) {
      intent = normalizeIntent intent;
    }
    // extra
    // routeExtra;

  mkRoute6 =
    {
      dst,
      via6,
      proto,
      intent ? null,
      extra ? { },
      routeExtra ? { },
    }:
    {
      dst = if dst == default6 then default6 else canonicalCidr dst;
      inherit via6 proto;
    }
    // lib.optionalAttrs (normalizeIntent intent != null) {
      intent = normalizeIntent intent;
    }
    // extra
    // routeExtra
    // lib.optionalAttrs (dst == default6) { preserveDst = true; };
}
