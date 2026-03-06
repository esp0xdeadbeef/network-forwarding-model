{ lib }:

{
  build = { lib, site, rolesResult, wanResult }:
    let
      communication = site.communicationContract or { };
      nat = communication.nat or { };
      ingress = nat.ingress or [ ];
      uplinkCoreByName = wanResult.uplinkCoreByName or { };

      refsOf =
        x:
        if !builtins.isAttrs x then
          [ ]
        else
          lib.filter (v: v != null && v != "") [
            (x.external or null)
            (x.fromExternal or null)
            (x.toExternal or null)
            (x.uplink or null)
          ];

      zpad =
        w: s:
        let
          s' = toString s;
          n = builtins.stringLength s';
        in
        builtins.concatStringsSep "" (builtins.genList (_: "0") (lib.max 0 (w - n))) + s';

      ruleKey = r:
        "${zpad 10 (r.source.priority or 0)}|${zpad 10 (r.source.index or 0)}|${toString (r.source.id or r.id or "")}";

      refs = lib.unique (refsOf nat ++ lib.concatMap refsOf ingress);
      knownRefs = lib.filter (r: uplinkCoreByName ? "${r}") refs;
    in
    {
      _nat = {
        mode = if (nat.enabled or false) || ingress != [ ] then "custom" else "none";
        owner =
          if knownRefs == [ ] then null
          else uplinkCoreByName.${builtins.head (lib.sort (a: b: a < b) knownRefs)};
        inherit ingress;
      };

      _enforcement = {
        owner = if rolesResult.policyUnit == null then null else toString rolesResult.policyUnit;
        rules = lib.sort (a: b: ruleKey a < ruleKey b) (lib.filter builtins.isAttrs (communication.allowedRelations or [ ]));
        validExternalRefs = builtins.attrNames uplinkCoreByName;
      };
    };
}
