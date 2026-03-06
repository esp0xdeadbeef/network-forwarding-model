{ lib }:
{ input }:

let
  solveEnterprise = import ./solver { inherit lib; };
  invariants = import ../lib/fabric/invariants/default.nix { inherit lib; };

  sitesByEnterprise =
    if input ? sites && builtins.isAttrs input.sites then
      input.sites
    else
      throw ''
        network-solver: expected compiler IR with top-level attribute 'sites'

        ===== FULL INPUT IR =====
        ${builtins.toJSON input}
      '';

  compilerMeta =
    if input ? meta && builtins.isAttrs input.meta && input.meta ? compiler && builtins.isAttrs input.meta.compiler then
      input.meta.compiler
    else
      { };

  solvedSitesByEnterprise =
    builtins.mapAttrs
      (ent: sites:
        let
          solved = solveEnterprise { enterprise = ent; inherit sites; };
          _ = builtins.mapAttrs (_: site: invariants.checkSite { inherit site; }) solved;
        in
        solved)
      sitesByEnterprise;

  flattenedSolvedSites =
    builtins.foldl'
      (acc: ent:
        acc
        // builtins.mapAttrs
          (siteId: site: site)
          (builtins.mapAttrs' (siteId: site: {
            name = "${ent}.${siteId}";
            value = site;
          }) solvedSitesByEnterprise.${ent}))
      { }
      (builtins.attrNames solvedSitesByEnterprise);

  _ = invariants.checkAll { sites = flattenedSolvedSites; };

in
{
  meta = {
    compiler = compilerMeta;
    solver = {
      name = "network-solver";
      schemaVersion = 2;
    };
  };

  sites = solvedSitesByEnterprise;
}
