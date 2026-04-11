{ lib }:

let
  common = import ./common.nix { inherit lib; };
  enterprise = import ./enterprise-utils.nix { inherit lib; };
  iface = import ./interface-utils.nix { inherit lib; };

  loopbackEntriesFrom =
    {
      whereBase,
      lb,
      extra ? { },
    }:
    if !(builtins.isAttrs lb) then
      [ ]
    else
      lib.flatten [
        (lib.optional (lb ? ipv4 && lb.ipv4 != null) (
          {
            family = "addr4";
            ip = common.stripMask lb.ipv4;
            where = "${whereBase}.ipv4";
          }
          // extra
        ))
        (lib.optional (lb ? ipv6 && lb.ipv6 != null) (
          {
            family = "addr6";
            ip = common.stripMask lb.ipv6;
            where = "${whereBase}.ipv6";
          }
          // extra
        ))
      ];

  collectSite =
    siteKey: site:
    let
      nodes = site.nodes or { };

      nodeEntries = lib.concatMap (
        nodeName:
        let
          node = nodes.${nodeName};

          nodeIfaces = iface.ifaceEntriesFrom {
            whereBase = "${siteKey}:nodes.${nodeName}.interfaces";
            ifaces = node.interfaces or { };
          };

          nodeLoopback = loopbackEntriesFrom {
            whereBase = "${siteKey}:nodes.${nodeName}.loopback";
            lb = node.loopback or { };
          };

          contEntries = lib.concatMap (
            cname:
            let
              c = node.${cname} or { };
            in
            (iface.ifaceEntriesFrom {
              whereBase = "${siteKey}:nodes.${nodeName}.${cname}.interfaces";
              ifaces = c.interfaces or { };
            })
            ++ (loopbackEntriesFrom {
              whereBase = "${siteKey}:nodes.${nodeName}.${cname}.loopback";
              lb = c.loopback or { };
            })
          ) (common.containersOf node);
        in
        nodeIfaces ++ nodeLoopback ++ contEntries
      ) (builtins.attrNames nodes);
    in
    iface.nonEmptyEntries nodeEntries;

  checkUniq =
    { entName, entries }:
    let
      step =
        acc: e:
        let
          k = "${e.family}:${toString e.ip}";
        in
        if acc.seen ? "${k}" then
          throw ''
            invariants(enterprise-no-duplicate-addrs):

            (enterprise: ${entName})

            duplicate address generated within enterprise

            address: ${toString e.ip}   (${e.family})

            first seen at:
            ${acc.seen.${k}}

            duplicated at:
            ${e.where}
          ''
        else
          {
            seen = acc.seen // {
              "${k}" = e.where;
            };
          };

      _ = builtins.foldl' step { seen = { }; } entries;
    in
    true;

in
{
  checkAll =
    { sites }:
    let
      byEnt = enterprise.groupByEnterprise sites;

      checkEnt =
        entName:
        let
          entSites = byEnt.${entName};
          siteKeys = builtins.attrNames entSites;

          entries = lib.concatMap (k: collectSite k entSites.${k}) siteKeys;
        in
        checkUniq { inherit entName entries; };

      _ = lib.forEach (builtins.attrNames byEnt) checkEnt;
    in
    builtins.deepSeq _ true;
}
