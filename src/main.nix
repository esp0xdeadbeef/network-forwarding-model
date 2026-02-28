# ./src/main.nix
{ lib }:
{ input }:

let
  inputJson = builtins.toJSON input;

  dump = x: builtins.toJSON x;

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
    let
      eval = builtins.tryEval (invariants.checkSite { inherit site; });
    in
    if eval.success then
      { ok = true; }
    else
      throw ''
        network-solver: invariants failed

        ===== ENTERPRISE =====
        ${ent}

        ===== SITE =====
        ${siteId}

        ===== INVARIANT ERROR (raw) =====
        ${if eval ? value then dump eval.value else "<no value>"}

        ===== SOLVED SITE IR =====
        ${dump site}

        ===== SOLVED ENTERPRISE IR =====
        ${dump { "${ent}" = { "${siteId}" = site; }; }}

        ===== FULL INPUT IR =====
        ${inputJson}
      '';

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

in
{
  meta = {
    solver = {
      name = "network-solver";
      schemaVersion = 2;
    };
  };

  sites = solvedSitesByEnterprise;
}
