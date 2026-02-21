{ lib }:

let

  stripMask =
    s:
    let
      parts = lib.splitString "/" (toString s);
    in
    if builtins.length parts == 0 then "" else builtins.elemAt parts 0;

  assert_ = cond: msg: if cond then true else throw msg;

  enterpriseOf =
    siteKey: site:
    if site ? enterprise && builtins.isString site.enterprise then
      site.enterprise
    else
      let
        parts = lib.splitString "." siteKey;
      in
      if builtins.length parts >= 2 then builtins.elemAt parts 0 else "__default__";

  groupByEnterprise =
    sites:
    builtins.foldl' (
      acc: siteKey:
      let
        site = sites.${siteKey};
        e = enterpriseOf siteKey site;
      in
      acc
      // {
        "${e}" = (acc."${e}" or { }) // {
          "${siteKey}" = site;
        };
      }
    ) { } (builtins.attrNames sites);

  isContainerAttr =
    name: v:
    builtins.isAttrs v
    && !(lib.elem name [
      "role"
      "networks"
      "interfaces"
    ]);

  containersOf = node: builtins.attrNames (lib.filterAttrs isContainerAttr node);

  ifaceEntriesFrom =
    { whereBase, ifaces }:
    if !(builtins.isAttrs ifaces) then
      [ ]
    else
      lib.concatMap (
        ifName:
        let
          iface = ifaces.${ifName};

          mk = fam: addr: {
            family = fam;
            ip = stripMask addr;
            where = "${whereBase}.${ifName}.${fam}";
          };
        in
        lib.flatten [
          (lib.optional (iface ? addr4 && iface.addr4 != null) (mk "addr4" iface.addr4))
          (lib.optional (iface ? addr6 && iface.addr6 != null) (mk "addr6" iface.addr6))
        ]
      ) (builtins.attrNames ifaces);

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
              ip = stripMask addr;
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
          topIfs = node.interfaces or { };

          conts = containersOf node;

          contEntries = lib.concatMap (
            cname:
            let
              c = node.${cname} or { };
            in
            ifaceEntriesFrom {
              whereBase = "${siteKey}:nodes.${nodeName}.${cname}.interfaces";
              ifaces = c.interfaces or { };
            }
          ) conts;
        in
        (ifaceEntriesFrom {
          whereBase = "${siteKey}:nodes.${nodeName}.interfaces";
          ifaces = topIfs;
        })
        ++ contEntries
      ) (builtins.attrNames nodes);

      entries = linkEntries ++ nodeEntries;
    in
    lib.filter (e: (toString e.ip) != "") entries;

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
      byEnt = groupByEnterprise sites;

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
