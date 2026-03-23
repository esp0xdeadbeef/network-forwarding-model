{ lib }:

let
  ip = import ../../../../lib/net/ip-utils.nix { inherit lib; };
  cidr = import ../../../../lib/fabric/invariants/cidr-utils.nix { inherit lib; };
  network = import ../../../../lib/model/network-utils.nix { inherit lib; };
  common = import ./common.nix { inherit lib; };

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

  explicitLoopbackFromSite =
    site: unitName:
    let
      base = common.nodeFromSite site unitName;
    in
    if base ? loopback then
      common.normalizeLoopback base.loopback
    else if site ? routerLoopbacks && site.routerLoopbacks ? "${unitName}" then
      common.normalizeLoopback site.routerLoopbacks.${unitName}
    else
      null;

  userPrefixEntriesFromNodes =
    nodes:
    lib.concatMap (
      nodeName:
      let
        node = nodes.${nodeName};
        nets = network.networksOfRaw {
          extraExcluded = [
            "containers"
            "uplinks"
            "loopback"
            "routingDomain"
          ];
        } node;
      in
      lib.concatMap (
        netName:
        let
          net = nets.${netName};
        in
        lib.flatten [
          (lib.optional (net ? ipv4 && net.ipv4 != null) {
            family = 4;
            cidr = toString net.ipv4;
            label = "nodes.${nodeName}.networks.${netName}.ipv4";
          })
          (lib.optional (net ? ipv6 && net.ipv6 != null) {
            family = 6;
            cidr = toString net.ipv6;
            label = "nodes.${nodeName}.networks.${netName}.ipv6";
          })
        ]
      ) (builtins.attrNames nets)
    ) (builtins.attrNames nodes);

  explicitLoopbackEntriesFromUnits =
    site: unitNames:
    lib.concatMap (
      unitName:
      let
        lb = explicitLoopbackFromSite site unitName;
      in
      if lb == null then
        [ ]
      else
        lib.flatten [
          (lib.optional ((lb.ipv4 or null) != null) {
            family = 4;
            addr = toString lb.ipv4;
            label = "nodes.${unitName}.loopback.ipv4";
          })
          (lib.optional ((lb.ipv6 or null) != null) {
            family = 6;
            addr = toString lb.ipv6;
            label = "nodes.${unitName}.loopback.ipv6";
          })
        ]
    ) unitNames;

  wanAddressEntriesFromLinks =
    links:
    lib.concatMap (
      linkName:
      let
        link = links.${linkName};
        eps = link.endpoints or { };
      in
      lib.concatMap (
        nodeName:
        let
          ep = eps.${nodeName};
        in
        lib.flatten [
          (lib.optional ((ep.addr4 or null) != null) {
            family = 4;
            addr = toString ep.addr4;
            label = "links.${linkName}.endpoints.${nodeName}.addr4";
          })
          (lib.optional ((ep.peerAddr4 or null) != null) {
            family = 4;
            addr = toString ep.peerAddr4;
            label = "links.${linkName}.endpoints.${nodeName}.peerAddr4";
          })
          (lib.optional ((ep.addr6 or null) != null) {
            family = 6;
            addr = toString ep.addr6;
            label = "links.${linkName}.endpoints.${nodeName}.addr6";
          })
          (lib.optional ((ep.peerAddr6 or null) != null) {
            family = 6;
            addr = toString ep.peerAddr6;
            label = "links.${linkName}.endpoints.${nodeName}.peerAddr6";
          })
        ]
      ) (builtins.attrNames eps)
    ) (builtins.attrNames links);

in
{
  inherit
    validatePool
    assertNoOverlap
    assertHostInPool
    explicitLoopbackFromSite
    userPrefixEntriesFromNodes
    explicitLoopbackEntriesFromUnits
    wanAddressEntriesFromLinks
    ;
}
