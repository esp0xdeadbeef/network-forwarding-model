{ lib, self ? { outPath = ./.; }, ... }:
{ input }:

let
  trace = import (self.outPath + "/lib/trace.nix") { };

  config = input;

  normalizeSites = import (self.outPath + "/compiler-input/sites/build.nix") { inherit lib self; };
  normalizedSitesByEnterprise = trace.emit "build:normalize-sites" (normalizeSites { inherit config; });

  flatSites = import (self.outPath + "/implementation/s88/build/flat-sites.nix") { inherit lib self; };
  contracts = import (self.outPath + "/implementation/s88/build/contracts.nix") { inherit lib self; };
  overlayTraversalWarnings = import (self.outPath + "/implementation/s88/build/overlay-traversal-warnings.nix") {
    inherit lib self;
  } flatSolvedSites;

  solver = import ./Enterprise/build.nix { inherit lib self; };

  solverResultByEnterprise = trace.emit "build:solve-enterprises" (builtins.mapAttrs (
    enterpriseName: sites:
    solver {
      enterprise = enterpriseName;
      inherit sites;
      allSites = normalizedSitesByEnterprise;
    }
  ) normalizedSitesByEnterprise);

  solvedSitesByEnterprise =
    trace.emit "build:extract-solved-sites" (builtins.mapAttrs flatSites.extractSolvedSites solverResultByEnterprise);

  flatSolvedSites = trace.emit "build:flatten-sites" (flatSites.flatten solvedSitesByEnterprise);

  invariants = import (self.outPath + "/lib/fabric/invariants") { inherit lib self; };
  skipInvariants = builtins.getEnv "S88_NFM_PROFILE_SKIP_INVARIANTS" == "1";

  _siteInvariantChecks =
    if skipInvariants then
      true
    else
      trace.emit "build:site-invariants" (builtins.deepSeq (builtins.attrValues (
        builtins.mapAttrs (_: site: invariants.checkSite { inherit site; }) flatSolvedSites
      )) true);

  _globalInvariantChecks =
    if skipInvariants then
      true
    else
      trace.emit "build:global-invariants" (invariants.checkAll { sites = flatSolvedSites; });

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
