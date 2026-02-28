# ./src/main.nix
{ lib }:
{ input }:

let
  _withInputContext =
    builtins.addErrorContext
      ("network-solver: input IR (for deterministic debugging)\n\n" + builtins.toJSON input)
      true;

  sitesByEnterprise =
    if input ? sites && builtins.isAttrs input.sites then
      input.sites
    else
      throw "network-solver: expected compiler IR with top-level attribute 'sites'";

  solveEnterprise = import ./solver { inherit lib; };

  invariants = import ../lib/fabric/invariants/default.nix { inherit lib; };

  solverGitRev =
    let
      v = builtins.getEnv "GIT_REV";
    in
    if v == "" then null else v;

  solverGitDirty =
    let
      v = builtins.getEnv "GIT_DIRTY";
    in
    if v == "" then null else (v == "1" || v == "true" || v == "yes");

  solverMeta = {
    schemaVersion = 1;
    solver = "network-solver";
    git = {
      rev = solverGitRev;
      dirty = solverGitDirty;
    };
  };

  inputMeta =
    if input ? meta && builtins.isAttrs input.meta then input.meta else null;

  validateSite =
    { siteKey, site }:
    let
      eval = builtins.tryEval (invariants.checkSite { inherit site; });
    in
    if eval.success then
      {
        ok = true;
      }
    else
      {
        ok = false;
        error = "invariants.checkSite failed";
        siteKey = siteKey;
      };

  solveAndValidateEnterprise =
    ent:
    let
      solved =
        solveEnterprise {
          enterprise = ent;
          sites = sitesByEnterprise.${ent};
        };

      perSiteResults =
        builtins.foldl'
          (acc: siteId:
            let
              siteKey = "${ent}.${siteId}";
              site0 = solved.${siteId};
              res = validateSite { inherit siteKey; site = site0; };
              site1 =
                site0
                // {
                  _verification = (site0._verification or { }) // {
                    invariants = res;
                  };
                };
            in
            acc
            // {
              sites = (acc.sites or { }) // { "${siteId}" = site1; };
              results = (acc.results or { }) // { "${siteKey}" = res; };
            })
          { }
          (builtins.attrNames solved);

      _enforce =
        let
          failed =
            lib.filterAttrs (_: v: !(v.ok or false)) (perSiteResults.results or { });
        in
        if failed == { } then
          true
        else
          throw ("network-solver: invariants failed\n\n" + builtins.toJSON failed);
    in
    builtins.seq _enforce (perSiteResults.sites or { });

  solvedSitesByEnterprise =
    builtins.foldl'
      (acc: ent:
        acc // {
          "${ent}" = solveAndValidateEnterprise ent;
        })
      { }
      (builtins.attrNames sitesByEnterprise);

in
builtins.seq _withInputContext {
  meta =
    solverMeta
    // {
      provenance =
        if inputMeta == null then null else inputMeta;
    };

  sites = solvedSitesByEnterprise;
}
