{ lib }:
{ input }:

let
  inputJson = builtins.toJSON input;

  solveEnterprise = import ./solver { inherit lib; };

  invariants = import ../lib/fabric/invariants/default.nix { inherit lib; };

  sitesByEnterprise =
    if input ? sites && builtins.isAttrs input.sites then
      input.sites
    else
      throw ''
        network-solver: expected compiler IR with top-level attribute 'sites'

        ===== FULL INPUT IR =====
        ${inputJson}
      '';

  validateSite =
    { ent, siteId, site }:
    invariants.checkSite { inherit site; };

  solveAndValidateEnterprise =
    ent:
    let
      solved =
        solveEnterprise {
          enterprise = ent;
          sites = sitesByEnterprise.${ent};
        };

      siteIds = lib.sort (a: b: a < b) (builtins.attrNames solved);

      validated =
        builtins.foldl'
          (acc: siteId:
            let
              site0 = solved.${siteId};
              _ = validateSite { inherit ent siteId; site = site0; };
            in
            acc // { "${siteId}" = site0; }
          )
          { }
          siteIds;
    in
      validated;

  enterpriseNames =
    lib.sort (a: b: a < b) (builtins.attrNames sitesByEnterprise);

  solvedSitesByEnterprise =
    builtins.foldl'
      (acc: ent:
        acc // {
          "${ent}" = solveAndValidateEnterprise ent;
        })
      { }
      enterpriseNames;

  flattenedSolvedSites =
    builtins.foldl'
      (acc: ent:
        let
          sites = solvedSitesByEnterprise.${ent};
          siteIds = lib.sort (a: b: a < b) (builtins.attrNames sites);
        in
        builtins.foldl'
          (acc2: siteId:
            acc2 // {
              "${ent}.${siteId}" = sites.${siteId};
            })
          acc
          siteIds)
      { }
      enterpriseNames;

  _finalValidation = invariants.checkAll { sites = flattenedSolvedSites; };

in
builtins.seq _finalValidation {
  meta = {
    solver = {
      name = "network-solver";
      schemaVersion = 2;
    };
  };

  sites = solvedSitesByEnterprise;
}
