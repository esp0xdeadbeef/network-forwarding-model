{ lib }:

let
  enterprise = import ./enterprise-utils.nix { inherit lib; };

  keyForLink =
    linkName: link:
    let
      linkId = link.id or null;
    in
    if linkId != null then
      {
        key = "id:${toString linkId}";
        kind = "stable link identity";
        value = toString linkId;
      }
    else
      {
        key = "name:${toString linkName}";
        kind = "link name";
        value = toString linkName;
      };

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
                let
                  link = links.${linkName};
                  keyInfo = keyForLink linkName link;
                  renderedFirst = acc2.seen.${keyInfo.key} or null;
                  here = "${siteKey}:${linkName}";
                in
                if acc2.seen ? "${keyInfo.key}" then
                  throw ''
                    invariants(enterprise-no-duplicate-link-names):

                    (enterprise: ${entName})

                    duplicate ${keyInfo.kind} detected within enterprise:

                    ${keyInfo.value}

                    first seen at:
                    ${renderedFirst}

                    duplicated at:
                    ${here}
                  ''
                else
                  {
                    seen = acc2.seen // {
                      "${keyInfo.key}" = here;
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
