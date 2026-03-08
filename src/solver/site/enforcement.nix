{ lib }:

{
  build =
    {
      lib,
      site,
      rolesResult,
      wanResult,
    }:
    let
      uplinkCoreByName = wanResult.uplinkCoreByName or { };
    in
    {
      _nat = {
        mode = "none";
        owner = null;
        ingress = [ ];
      };

      _enforcement = {
        owner = if rolesResult.policyUnit == null then null else toString rolesResult.policyUnit;
        rules = [ ];
        validExternalRefs = builtins.attrNames uplinkCoreByName;
      };
    };
}
