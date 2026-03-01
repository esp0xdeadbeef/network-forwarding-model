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
      communication = site.communicationContract or { };

      nat0 = communication.nat or { };
      natIngress = nat0.ingress or [ ];

      natMode =
        if (nat0.enabled or false) == true then
          "custom"
        else if builtins.length natIngress > 0 then
          "custom"
        else
          "none";

      natRealized = {
        mode = natMode;
        owner =
          if wanResult ? coreUnit && wanResult.coreUnit != null
          then toString wanResult.coreUnit
          else null;
        ingress = natIngress;
      };

      zpad =
        w: s:
        let
          str = toString s;
          len = builtins.stringLength str;
          zeros =
            builtins.concatStringsSep ""
              (builtins.genList (_: "0") (lib.max 0 (w - len)));
        in
        zeros + str;

      ruleKey =
        r:
        let
          p = toString (r.source.priority or 0);
          i = toString (r.source.index or 0);
          id = toString (r.source.id or r.id or "");
        in
        "${zpad 10 p}|${zpad 10 i}|${id}";

      enforcementRules =
        let
          rs0 = communication.allowedRelations or [ ];
          rs1 = lib.filter builtins.isAttrs rs0;
        in
        lib.sort (a: b: ruleKey a < ruleKey b) rs1;

      policyOwner =
        if rolesResult ? policyUnit && rolesResult.policyUnit != null
        then toString rolesResult.policyUnit
        else null;

    in
    {
      _nat = natRealized;

      _enforcement = {
        owner = policyOwner;
        rules = enforcementRules;
      };
    };
}
