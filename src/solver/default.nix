{ lib }:

{ enterprise
, sites
}:

let
  _ =
    if builtins.isAttrs sites then true
    else throw "network-solver: sites.${enterprise} must be an attrset";

  solveSite = import ./site.nix { inherit lib; };
in
builtins.foldl'
  (acc: siteId:
    acc // {
      "${siteId}" =
        solveSite {
          enterprise = enterprise;
          siteId = siteId;
          site = sites.${siteId};
        };
    })
  { }
  (builtins.attrNames sites)
