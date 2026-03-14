{ lib }:
{
  enterprise,
  sites,
  allSites ? {
    "${enterprise}" = sites;
  },
}:
let
  solveSite = import ./site.nix { inherit lib; };
in
if !builtins.isAttrs sites then
  throw "network-solver: sites.${enterprise} must be an attrset"
else
  builtins.mapAttrs (
    siteId: site:
    solveSite {
      inherit enterprise siteId site;
      sites = allSites;
    }
  ) sites
