{ lib, self ? { outPath = ./.; }, ... }:
{ input }:

let
  config = input;

  normalizeSites = import (self.outPath + "/compiler-input/sites/build.nix") { inherit lib self; };
  normalizedSitesByEnterprise = normalizeSites { inherit config; };

  flatSites = import (self.outPath + "/implementation/s88/build/flat-sites.nix") { inherit lib self; };
  contracts = import (self.outPath + "/implementation/s88/build/contracts.nix") { inherit lib self; };
  overlayTraversalWarnings = import (self.outPath + "/implementation/s88/build/overlay-traversal-warnings.nix") {
    inherit lib self;
  } flatSolvedSites;

  solver = import ./Enterprise/build.nix { inherit lib self; };

  solverResultByEnterprise = builtins.mapAttrs (
    enterpriseName: sites:
    solver {
      enterprise = enterpriseName;
      inherit sites;
      allSites = normalizedSitesByEnterprise;
    }
  ) normalizedSitesByEnterprise;

  solvedSitesByEnterprise = builtins.mapAttrs flatSites.extractSolvedSites solverResultByEnterprise;

  flatSolvedSites = flatSites.flatten solvedSitesByEnterprise;

  invariants = import (self.outPath + "/lib/fabric/invariants") { inherit lib self; };

  _siteInvariantChecks = builtins.deepSeq (builtins.attrValues (
    builtins.mapAttrs (_: site: invariants.checkSite { inherit site; }) flatSolvedSites
  )) true;

  _globalInvariantChecks = invariants.checkAll { sites = flatSolvedSites; };

  enterpriseNames = builtins.attrNames solverResultByEnterprise;

  firstEnterpriseName = if enterpriseNames == [ ] then null else builtins.head enterpriseNames;

  firstSolverResult =
    if firstEnterpriseName == null then { } else solverResultByEnterprise.${firstEnterpriseName};

  inheritedMeta =
    if builtins.isAttrs firstSolverResult && firstSolverResult ? meta then
      firstSolverResult.meta
    else
      { };

  result = {
    enterprise = builtins.mapAttrs (_: sites: { site = sites; }) solvedSitesByEnterprise;

    meta = inheritedMeta // {
      networkForwardingModel = (inheritedMeta.networkForwardingModel or { }) // {
        name = "network-forwarding-model";
        schemaVersion = 9;
        inherit contracts;
        warningMessages = lib.unique (
          (inheritedMeta.networkForwardingModel.warningMessages or [ ]) ++ overlayTraversalWarnings
        );
      };
    };
  };
in
builtins.seq _siteInvariantChecks (builtins.seq _globalInvariantChecks result)
