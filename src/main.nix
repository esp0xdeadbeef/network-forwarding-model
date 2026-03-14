{ lib }:
{ input }:

let
  solveEnterprise = import ./solver { inherit lib; };
  invariants = import ../lib/fabric/invariants/default.nix { inherit lib; };

  sitesByEnterprise =
    if input ? sites && builtins.isAttrs input.sites then
      input.sites
    else
      throw ''
        network-solver: expected compiler IR with top-level attribute 'sites'

        ===== FULL INPUT IR =====
        ${builtins.toJSON input}
      '';

  originalInputs =
    if
      input ? meta
      && builtins.isAttrs input.meta
      && input.meta ? provenance
      && builtins.isAttrs input.meta.provenance
      && input.meta.provenance ? originalInputs
      && builtins.isAttrs input.meta.provenance.originalInputs
    then
      input.meta.provenance.originalInputs
    else
      { };

  originalSiteFor =
    ent: siteId:
    if
      originalInputs ? "${ent}"
      && builtins.isAttrs originalInputs.${ent}
      && originalInputs.${ent} ? "${siteId}"
    then
      originalInputs.${ent}.${siteId}
    else
      { };

  enrichSite =
    ent: siteId: site:
    let
      original = originalSiteFor ent siteId;

      originalTopology =
        if original ? topology && builtins.isAttrs original.topology then original.topology else { };

      originalTopologyNodes =
        if originalTopology ? nodes && builtins.isAttrs originalTopology.nodes then
          originalTopology.nodes
        else
          { };

      existingTopology = if site ? topology && builtins.isAttrs site.topology then site.topology else { };

      existingTopologyNodes =
        if existingTopology ? nodes && builtins.isAttrs existingTopology.nodes then
          existingTopology.nodes
        else
          { };
    in
    site
    // {
      topology = existingTopology // {
        nodes = originalTopologyNodes // existingTopologyNodes;
      };
    };

  solvedSitesByEnterprise = builtins.mapAttrs (
    ent: sites:
    let
      solved = solveEnterprise {
        enterprise = ent;
        sites = builtins.mapAttrs (siteId: site: enrichSite ent siteId site) sites;
      };
      _ = builtins.mapAttrs (_: site: invariants.checkSite { inherit site; }) solved;
    in
    solved
  ) sitesByEnterprise;

  flattenedSolvedSites = builtins.foldl' (
    acc: ent:
    acc
    // builtins.mapAttrs (_: site: site) (
      builtins.mapAttrs' (siteId: site: {
        name = "${ent}.${siteId}";
        value = site;
      }) solvedSitesByEnterprise.${ent}
    )
  ) { } (builtins.attrNames solvedSitesByEnterprise);

  _ = invariants.checkAll { sites = flattenedSolvedSites; };

in
{
  meta = {
    solver = {
      name = "network-solver";
      schemaVersion = 5;
    };
  };

  enterprise = builtins.mapAttrs (_: sites: { site = sites; }) solvedSitesByEnterprise;
}
