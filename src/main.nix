{ lib }:
{ input }:

let
  sitesByEnterprise =
    if input ? sites && builtins.isAttrs input.sites then
      input.sites
    else
      throw "network-solver: expected compiler IR with top-level attribute 'sites'";

  solveEnterprise = import ./solver { inherit lib; };

  solvedSitesByEnterprise =
    builtins.foldl'
      (acc: ent:
        acc // {
          "${ent}" =
            solveEnterprise {
              enterprise = ent;
              sites = sitesByEnterprise.${ent};
            };
        })
      { }
      (builtins.attrNames sitesByEnterprise);

in
{
  meta = {
    schemaVersion = 1;
    solver = "network-solver";
  };

  sites = solvedSitesByEnterprise;
}
