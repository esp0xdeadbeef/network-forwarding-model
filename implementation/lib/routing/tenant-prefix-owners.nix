{ lib, self ? { outPath = ./.; }, ... }:

let
  helpers = import ./static-helpers.nix { inherit lib self; };

  build =
    topo:
    let
      nodes = topo.nodes or { };
      nodeNames = lib.sort (a: b: a < b) (builtins.attrNames nodes);

      entries = lib.concatMap (
        nodeName:
        map (
          e:
          e
          // {
            owner = nodeName;
          }
        ) (helpers.prefixEntriesFromNetworks nodes.${nodeName})
      ) nodeNames;

      step =
        acc: e:
        let
          routeIdentity =
            if e ? dst then
              e.dst
            else if e ? sourceFile then
              "source:${e.sourceFile}"
            else
              null;
          k = "${toString e.family}|${routeIdentity}";
        in
        if routeIdentity == null then
          acc
        else
        if acc ? "${k}" then
          let
            prev = acc.${k};
          in
          if prev.owner == e.owner then
            acc
          else
            throw "tenant-prefix-owners: prefix '${e.dst}' has multiple owners ('${prev.owner}' via '${prev.netName}' and '${e.owner}' via '${e.netName}')"
        else
          acc
          // {
            "${k}" = {
              family = e.family;
              owner = e.owner;
              netName = e.netName or null;
            }
            // lib.optionalAttrs (e ? dst) { dst = e.dst; }
            // lib.optionalAttrs (e ? sourceFile) {
              sourceFile = e.sourceFile;
              prefixName = e.prefixName or null;
              kind = e.kind or "runtime-routed-prefix";
              delegatedPrefixLength = e.delegatedPrefixLength or null;
              perTenantPrefixLength = e.perTenantPrefixLength or null;
              slot = e.slot or null;
            }
            // lib.optionalAttrs ((e.prefixPostfix or null) != null) { prefixPostfix = e.prefixPostfix; };
          };

    in
    builtins.foldl' step { } entries;

in
{
  inherit build;
}
