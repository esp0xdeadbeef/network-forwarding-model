{ lib }:

let
  cidr = import ./cidr-utils.nix { inherit lib; };
  common = import ./common.nix { inherit lib; };

  hostRange4 = ip: cidr.cidrRange "${common.stripMask ip}/32";
  hostRange6 = ip: cidr.cidrRange "${common.stripMask ip}/128";

  inRange =
    poolRange: hostRange:
    poolRange.family == hostRange.family
    && poolRange.start <= hostRange.start
    && hostRange.end <= poolRange.end;

  checkOne =
    {
      siteName,
      nodeName,
      fam,
      addr,
      pool,
    }:
    let
      poolRange = cidr.cidrRange pool;
      hostRange = if fam == 4 then hostRange4 addr else hostRange6 addr;
    in
    common.assert_ (inRange poolRange hostRange) ''
      invariants(loopbacks-in-local-pool):

      loopback addresses must be inside addressPools.local

        site: ${siteName}
        node: ${nodeName}
        family: IPv${toString fam}

        loopback:  ${toString addr}
        localPool: ${toString pool}
    '';

in
{
  check =
    { site }:
    let
      siteName = toString (site.siteName or "<unknown-site>");
      pools = site.addressPools or { };
      local = pools.local or { };

      pool4 = local.ipv4 or null;
      pool6 = local.ipv6 or null;

      nodeLoopbacks = builtins.foldl' (
        acc: nodeName:
        let
          node = (site.nodes or { }).${nodeName};
          lb = node.loopback or null;
        in
        if lb == null || !(builtins.isAttrs lb) then acc else acc // { "${nodeName}" = lb; }
      ) { } (builtins.attrNames (site.nodes or { }));

      lbs = if nodeLoopbacks != { } then nodeLoopbacks else site.routerLoopbacks or { };

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
                inherit siteName nodeName;
                fam = 4;
                addr = a4;
                pool = pool4;
              };

          _6 =
            if a6 == null || pool6 == null then
              true
            else
              checkOne {
                inherit siteName nodeName;
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
