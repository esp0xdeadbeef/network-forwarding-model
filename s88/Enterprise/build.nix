{ lib, self ? { outPath = ./.; }, ... }:
{
  enterprise,
  sites,
  allSites ? {
    "${enterprise}" = sites;
  },
}:
let
  buildSiteForwardingModel = import (self.outPath + "/s88/Site/build.nix") { inherit lib self; };
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
