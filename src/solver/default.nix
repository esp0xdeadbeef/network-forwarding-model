{ lib }:
{
  enterprise,
  sites,
  allSites ? {
    "${enterprise}" = sites;
  },
}:
let
  buildSiteForwardingModel = import ./site.nix { inherit lib; };
in
if !builtins.isAttrs sites then
  throw "network-forwarding-model: sites.${enterprise} must be an attrset"
else
  builtins.mapAttrs (
    siteId: site:
    buildSiteForwardingModel {
      inherit enterprise siteId site;
      sites = allSites;
    }
  ) sites
