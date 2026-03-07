{ lib }:

let
  common = import ./common.nix { inherit lib; };
  enterprise = import ./enterprise-utils.nix { inherit lib; };
  iface = import ./interface-utils.nix { inherit lib; };

  collectSite =
    siteKey: site:
    let
      links = site.links or { };
      nodes = site.nodes or { };

      linkEntries = lib.concatMap (
        linkName:
        let
          l = links.${linkName};
          eps = l.endpoints or { };
        in
        lib.concatMap (
          nodeName:
          let
            ep = eps.${nodeName};

            mk = fam: addr: {
              family = fam;
              ip = common.stripMask addr;
              where = "${siteKey}:links.${linkName}.endpoints.${nodeName}.${fam}";
            };
          in
          lib.flatten [
            (lib.optional (ep ? addr4 && ep.addr4 != null) (mk "addr4" ep.addr4))
            (lib.optional (ep ? addr6 && ep.addr6 != null) (mk "addr6" ep.addr6))
          ]
        ) (builtins.attrNames eps)
      ) (builtins.attrNames links);

      nodeEntries = lib.concatMap (
        nodeName:
        let
          node = nodes.${nodeName};

          contEntries = lib.concatMap (
            cname:
            let
              c = node.${cname} or { };
            in
            iface.ifaceEntriesFrom {
              whereBase = "${siteKey}:nodes.${nodeName}.${cname}.interfaces";
              ifaces = c.interfaces or { };
            }
          ) (common.containersOf node);
        in
        (iface.ifaceEntriesFrom {
          whereBase = "${siteKey}:nodes.${nodeName}.interfaces";
          ifaces = node.interfaces or { };
        })
        ++ contEntries
      ) (builtins.attrNames nodes);

      entries = linkEntries ++ nodeEntries;
    in
    iface.nonEmptyEntries entries;

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
