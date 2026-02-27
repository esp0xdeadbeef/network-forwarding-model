# ./lib/fabric/invariants/loopbacks-in-local-pool.nix
{ lib }:

let
  cidr = import ./cidr-utils.nix { inherit lib; };

  assert_ = cond: msg: if cond then true else throw msg;

  stripMask =
    s:
    let
      parts = lib.splitString "/" (toString s);
    in
    if builtins.length parts == 0 then "" else builtins.elemAt parts 0;

  # reuse range calc by turning a host into /32 or /128
  hostRange4 = ip: cidr.cidrRange "${stripMask ip}/32";
  hostRange6 = ip: cidr.cidrRange "${stripMask ip}/128";

  inRange = poolRange: hostRange:
    poolRange.family == hostRange.family
    && poolRange.start <= hostRange.start
    && hostRange.end <= poolRange.end;

  checkOne =
    { siteName, siteKey, nodeName, fam, addr, pool }:
    let
      poolRange = cidr.cidrRange pool;
      hostRange =
        if fam == 4 then hostRange4 addr else hostRange6 addr;
    in
    assert_ (inRange poolRange hostRange) ''
      invariants(loopbacks-in-local-pool):

      routerLoopbacks must be inside addressPools.local

        siteKey: ${siteKey}
        site:    ${siteName}
        node:    ${nodeName}
        family:  IPv${toString fam}

        loopback: ${toString addr}
        localPool: ${toString pool}
    '';

in
{
  check =
    { site }:
    let
      siteName = toString (site.siteName or "<unknown-site>");
      siteKey = toString (site.compilerIR.id or site.siteName or "<unknown-siteKey>");
      ir = site.compilerIR or { };

      pools = ir.addressPools or { };
      local = pools.local or { };

      pool4 = local.ipv4 or null;
      pool6 = local.ipv6 or null;

      lbs = ir.routerLoopbacks or { };

      nodes = builtins.attrNames lbs;

      checkNode =
        nodeName:
        let
          lb = lbs.${nodeName};

          a4 = lb.ipv4 or null;
          a6 = lb.ipv6 or null;

          _4 =
            if a4 == null || pool4 == null then
              true
            else
              checkOne {
                inherit siteName siteKey nodeName;
                fam = 4;
                addr = a4;
                pool = pool4;
              };

          _6 =
            if a6 == null || pool6 == null then
              true
            else
              checkOne {
                inherit siteName siteKey nodeName;
                fam = 6;
                addr = a6;
                pool = pool6;
              };
        in
        builtins.seq _4 (builtins.seq _6 true);

      done = lib.forEach nodes checkNode;
    in
    builtins.deepSeq done true;
}
