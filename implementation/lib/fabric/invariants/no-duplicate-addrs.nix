{ lib, self ? { outPath = ./.; }, ... }:

let
  common = import ./common.nix { inherit lib self; };
  iface = import ./interface-utils.nix { inherit lib self; };

  collectExecutionAddrs =
    site:
    let
      siteName = toString (site.siteName or "<unknown-site>");
      nodes = site.nodes or { };
    in
    iface.nonEmptyEntries (
      lib.concatMap
        (
          nodeName:
          let
            node = nodes.${nodeName};

            nodeIfs = iface.ifaceEntriesFrom {
              whereBase = "${siteName}:nodes.${nodeName}.interfaces";
              ifaces = node.interfaces or { };
              extra = {
                box = "${siteName}:${nodeName}";
              };
            };

            contIfs = lib.concatMap
              (
                cname:
                let
                  c = node.${cname} or { };
                in
                iface.ifaceEntriesFrom {
                  whereBase = "${siteName}:nodes.${nodeName}.${cname}.interfaces";
                  ifaces = c.interfaces or { };
                  extra = {
                    box = "${siteName}:${nodeName}.${cname}";
                  };
                }
              )
              (common.containersOf node);

            loopbackEntries =
              let
                lb = node.loopback or { };

                mk =
                  family: attr:
                  if !(lb ? "${attr}") || lb.${attr} == null then
                    [ ]
                  else
                    [
                      {
                        family = family;
                        ip = common.stripMask lb.${attr};
                        where = "${siteName}:nodes.${nodeName}.loopback.${attr}";
                        box = "${siteName}:${nodeName}";
                      }
                    ];
              in
              (mk "addr4" "ipv4") ++ (mk "addr6" "ipv6");
          in
          nodeIfs ++ contIfs ++ loopbackEntries
        )
        (builtins.attrNames nodes)
    );

  checkUniqAcrossBoxes =
    entries:
    let
      # Shared-tenant interfaces: access nodes with the same tenant get
      # the same derived addresses from the shared prefix. Allow duplicates
      # when both entries come from tenant interfaces with the same name.
      isTenantIface = where:
        builtins.match ".*\.interfaces\.tenant-.*" where != null;

      sameTenantIface = a: b:
        let
          ma = builtins.match ".*\.(interfaces\.tenant-[^.]+)\..*" a.where;
          mb = builtins.match ".*\.(interfaces\.tenant-[^.]+)\..*" b.where;
        in
        ma != null && mb != null && (builtins.head ma) == (builtins.head mb);

      step =
        acc: e:
        let
          k = "${e.family}:${toString e.ip}";
        in
        if acc.seen ? "${k}" then
          let
            prev = acc.seen.${k};
          in
          if sameTenantIface prev e then
            # Shared-tenant fabric (e.g. PPPoE combined fabric):
            # same tenant interface name on different access nodes;
            # addresses are derived from the same shared prefix.
            acc
          else
            throw ''
              invariants(no-duplicate-addrs):

              duplicate address across execution contexts (boxes)

              address: ${toString e.ip}   (${e.family})

              first seen at:
              ${prev.where}

              first seen in box:
              ${prev.box}

              duplicated at:
              ${e.where}

              duplicated in box:
              ${e.box}
            ''
        else
          acc
          // {
            seen = acc.seen // {
              "${k}" = {
                box = e.box;
                where = e.where;
              };
            };
          };

      st = builtins.foldl' step { seen = { }; } entries;
    in
    builtins.deepSeq st true;

in
{
  check =
    { site }:
    let
      entries = collectExecutionAddrs site;
    in
    checkUniqAcrossBoxes entries;
}
