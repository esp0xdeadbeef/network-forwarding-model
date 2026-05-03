{ lib }:

let
  ip = import ../../../../lib/net/ip-utils.nix { inherit lib; };
  cidr = import ../../../../lib/fabric/invariants/cidr-utils.nix { inherit lib; };
  entries = import ./pool-entries.nix { inherit lib; };

  overlaps = a: b: a.family == b.family && !(a.end < b.start || b.end < a.start);

  ceilLog2 =
    n:
    let
      go = bits: cap: if cap >= n then bits else go (bits + 1) (cap * 2);
    in
    if n <= 1 then 0 else go 0 1;

  validatePool =
    {
      label,
      family,
      cidrStr ? null,
      requiredHosts ? 0,
      required ? false,
    }:
    if cidrStr == null then
      if required || requiredHosts > 0 then
        throw ''
          network-forwarding-model: missing required pool

          pool: ${label}
        ''
      else
        true
    else
      let
        c = ip.splitCidr cidrStr;
        bits = if family == 4 then 32 else 128;
        hostBits = bits - c.prefix;
        needBits = ceilLog2 requiredHosts;

        _family =
          if family == 4 && !lib.hasInfix "." c.ip then
            throw ''
              network-forwarding-model: expected IPv4 CIDR

              pool: ${label}
              got: ${toString cidrStr}
            ''
          else if family == 6 && !lib.hasInfix ":" c.ip then
            throw ''
              network-forwarding-model: expected IPv6 CIDR

              pool: ${label}
              got: ${toString cidrStr}
            ''
          else
            true;

        _prefix =
          if c.prefix < 0 || c.prefix > bits then
            throw ''
              network-forwarding-model: invalid prefix length

              pool: ${label}
              got: ${toString cidrStr}
              bounds: 0..${toString bits}
            ''
          else
            true;

        _range = cidr.cidrRange cidrStr;

        _capacity =
          if requiredHosts <= 0 || hostBits >= needBits then
            true
          else
            throw ''
              network-forwarding-model: pool capacity exhausted

              pool: ${label}
              prefix: ${toString cidrStr}
              requiredHosts: ${toString requiredHosts}
            '';
      in
      builtins.seq _family (builtins.seq _prefix (builtins.seq _range _capacity));

  assertNoOverlap =
    {
      leftLabel,
      leftCidr,
      rightLabel,
      rightCidr,
    }:
    if leftCidr == null || rightCidr == null then
      true
    else
      let
        l = cidr.cidrRange leftCidr;
        r = cidr.cidrRange rightCidr;
      in
      if overlaps l r then
        throw ''
          network-forwarding-model: overlapping prefixes are not allowed

          left:  ${leftLabel}  (${toString leftCidr})
          right: ${rightLabel}  (${toString rightCidr})
        ''
      else
        true;

  hostRange =
    family: ip0: cidr.cidrRange "${ip.stripMask ip0}/${if family == 4 then "32" else "128"}";

  inRange =
    poolRange: hostRange0:
    poolRange.family == hostRange0.family
    && poolRange.start <= hostRange0.start
    && hostRange0.end <= poolRange.end;

  assertHostInPool =
    {
      poolLabel,
      poolCidr,
      entryLabel,
      family,
      addr0,
    }:
    if poolCidr == null || addr0 == null then
      true
    else
      let
        poolRange = cidr.cidrRange poolCidr;
        h = hostRange family addr0;
      in
      if inRange poolRange h then
        true
      else
        throw ''
          network-forwarding-model: host allocation is outside its required pool

          pool: ${poolLabel} (${toString poolCidr})
          entry: ${entryLabel} (${toString addr0})
        '';

in
{
  inherit
    validatePool
    assertNoOverlap
    assertHostInPool
    ;
  inherit (entries)
    explicitLoopbackEntriesFromUnits
    explicitLoopbackFromSite
    userPrefixEntriesFromNodes
    wanAddressEntriesFromLinks
    ;
}
