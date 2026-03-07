{ lib }:

let
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
in
{
  inherit enterpriseOf groupByEnterprise;
}
