{ lib, ... }:

{
  extractSolvedSites =
    enterpriseName: result:
    if builtins.isAttrs result && result ? site then
      result.site
    else if
      builtins.isAttrs result && result ? enterprise && builtins.hasAttr enterpriseName result.enterprise
    then
      let
        enterpriseResult = result.enterprise.${enterpriseName};
      in
      if builtins.isAttrs enterpriseResult && enterpriseResult ? site then
        enterpriseResult.site
      else
        enterpriseResult
    else
      result;

  flatten =
    solvedSitesByEnterprise:
    builtins.foldl' (
      acc: enterpriseName:
      let
        enterpriseSites = solvedSitesByEnterprise.${enterpriseName} or { };
      in
      acc
      // builtins.listToAttrs (
        map (siteId: {
          name = "${enterpriseName}.${siteId}";
          value = (enterpriseSites.${siteId}) // {
            enterprise = enterpriseSites.${siteId}.enterprise or enterpriseName;
            siteId = enterpriseSites.${siteId}.siteId or siteId;
            siteName = enterpriseSites.${siteId}.siteName or "${enterpriseName}.${siteId}";
          };
        }) (builtins.attrNames enterpriseSites)
      )
    ) { } (builtins.attrNames solvedSitesByEnterprise);
}
