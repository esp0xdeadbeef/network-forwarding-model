{ lib }:

let
  enterprise = import ./enterprise-utils.nix { inherit lib; };

in
{
  checkAll =
    { sites }:
    let
      byEnt = enterprise.groupByEnterprise sites;

      checkEnt =
        entName:
        let
          entSites = byEnt.${entName};
          siteKeys = builtins.attrNames entSites;

          stepSite =
            acc: siteKey:
            let
              site = entSites.${siteKey};
              links = site.links or { };

              stepLink =
                acc2: linkName:
                if acc2.seen ? "${linkName}" then
                  throw ''
                    invariants(enterprise-no-duplicate-link-names):

                    (enterprise: ${entName})

                    duplicate link name detected within enterprise:

                      ${linkName}

                    first seen in site:
                      ${acc2.seen.${linkName}}

                    duplicated in site:
                      ${siteKey}
                  ''
                else
                  {
                    seen = acc2.seen // {
                      "${linkName}" = siteKey;
                    };
                  };
            in
            builtins.foldl' stepLink acc (builtins.attrNames links);

          _ = builtins.foldl' stepSite { seen = { }; } siteKeys;
        in
        true;

      _all = lib.forEach (builtins.attrNames byEnt) checkEnt;
    in
    builtins.deepSeq _all true;
}
