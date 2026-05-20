{ lib, self ? { outPath = ./.; }, ... }:
{ enterprise
, sites
, allSites ? {
    "${enterprise}" = sites;
  }
,
}:
let
  trace = import (self.outPath + "/lib/trace.nix") { };
  buildSiteForwardingModel = import (self.outPath + "/s88/Site/build.nix") { inherit lib self; };
in
if !builtins.isAttrs sites then
  throw "network-forwarding-model: sites.${enterprise} must be an attrset"
else
  trace.emit "enterprise:${enterprise}:sites" (builtins.mapAttrs
    (
      siteId: site:
      buildSiteForwardingModel {
        inherit enterprise siteId site;
        sites = allSites;
      }
    )
    sites)
