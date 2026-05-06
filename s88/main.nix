{ lib, ... }:
{ input }:

let
  config = input;

  normalizeSites = import ./normalize-sites.nix { inherit lib; };
  normalizedSitesByEnterprise = normalizeSites { inherit config; };

  solver = import ./solver { inherit lib; };

  solverResultByEnterprise = builtins.mapAttrs (
    enterpriseName: sites:
    solver {
      enterprise = enterpriseName;
      inherit sites;
      allSites = normalizedSitesByEnterprise;
    }
  ) normalizedSitesByEnterprise;

  extractSolvedSites =
    enterpriseName: result:
    if builtins.isAttrs result && result ? site then
      result.site
    else if
      builtins.isAttrs result && result ? enterprise && builtins.hasAttr enterpriseName result.enterprise
    then
      let
        enterpriseResult = result.enterprise.${enterpriseName};
      in
      if builtins.isAttrs enterpriseResult && enterpriseResult ? site then
        enterpriseResult.site
      else
        enterpriseResult
    else
      result;

  solvedSitesByEnterprise = builtins.mapAttrs extractSolvedSites solverResultByEnterprise;

  flatSolvedSites = builtins.foldl' (
    acc: enterpriseName:
    let
      enterpriseSites = solvedSitesByEnterprise.${enterpriseName} or { };
      siteNames = builtins.attrNames enterpriseSites;
    in
    acc
    // builtins.listToAttrs (
      map (siteId: {
        name = "${enterpriseName}.${siteId}";
        value = (enterpriseSites.${siteId}) // {
          enterprise = (enterpriseSites.${siteId}.enterprise or enterpriseName);
          siteId = (enterpriseSites.${siteId}.siteId or siteId);
          siteName = (enterpriseSites.${siteId}.siteName or "${enterpriseName}.${siteId}");
        };
      }) siteNames
    )
  ) { } (builtins.attrNames solvedSitesByEnterprise);

  invariants = import ../lib/fabric/invariants { inherit lib; };

  _siteInvariantChecks = builtins.deepSeq (builtins.attrValues (
    builtins.mapAttrs (_: site: invariants.checkSite { inherit site; }) flatSolvedSites
  )) true;

  _globalInvariantChecks = invariants.checkAll { sites = flatSolvedSites; };

  overlayTraversalWarnings =
    let
      overlayWarningsForSite =
        siteKey: site:
        let
          overlayNames = builtins.attrNames (site.overlayReachability or { });
          linkNames = builtins.attrNames (site.links or { });
          hasAccessLaneForOverlay =
            overlayName:
            builtins.any (
              linkName: builtins.match ".*--access-.+--uplink-${overlayName}" linkName != null
            ) linkNames;
          overlayHasTermination =
            overlayName: ((site.overlayReachability.${overlayName}.terminateOn or [ ]) != [ ]);
        in
        lib.concatMap (
          overlayName:
          if overlayHasTermination overlayName && !(hasAccessLaneForOverlay overlayName) then
            [
              "network-forwarding-model: ${siteKey}: overlay '${overlayName}' terminates on core node(s) but has no access-specific uplink lane; Nebula overlay cores must be reached through access/policy traversal, so add an allowed relation from the intended access tenant(s) to external '${overlayName}'"
            ]
          else
            [ ]
        ) overlayNames;
    in
    lib.concatMap (siteKey: overlayWarningsForSite siteKey flatSolvedSites.${siteKey}) (
      builtins.attrNames flatSolvedSites
    );

  enterpriseNames = builtins.attrNames solverResultByEnterprise;

  firstEnterpriseName = if enterpriseNames == [ ] then null else builtins.head enterpriseNames;

  firstSolverResult =
    if firstEnterpriseName == null then { } else solverResultByEnterprise.${firstEnterpriseName};

  inheritedMeta =
    if builtins.isAttrs firstSolverResult && firstSolverResult ? meta then
      firstSolverResult.meta
    else
      { };

  contracts = {
    input = {
      site = {
        addressPools = {
          local = "required";
          p2p = "required";
        };
        domains = {
          tenants = "canonical";
        };
        forwardingSemantics = {
          nodes = "accepted-as-role-hints";
          coreNodeNames = "accepted-as-role-hints";
          policyNodeName = "accepted-as-role-hints";
          upstreamSelectorNodeName = "accepted-as-role-hints";
        };
        topology = {
          links = {
            directed = true;
            shape = "node-pairs";
            example = [
              [
                "<from-node>"
                "<to-node>"
              ]
            ];
          };
        };
      };
    };

    normalization = {
      site = {
        addressPools = {
          derived = true;
          source = "site.addressPools or site.pools";
        };
        domains = {
          tenants = {
            derived = true;
            source = "site.domains.tenants or site.ownership.prefixes[kind=tenant]";
          };
          externals = {
            derived = true;
            source = "site.domains.externals or site.policy.interfaceTags[external-*]";
          };
        };
        attachments = {
          derived = true;
          source = "site.attachments or site.topology.nodes.*.attachments";
        };
        roles = {
          derived = true;
          source = "site.topology.nodes.*.role or site.nodes.*.role or site.units.*.role or site.forwardingSemantics";
        };
        policy = {
          interfaceTags = {
            derived = true;
            source = "site.policy.interfaceTags merged with site.attachments and site.domains";
          };
        };
        transit = {
          nodePairOrdering = {
            derived = true;
            field = "site.transit.ordering";
            shape = "node-pairs";
            source = "site.topology.links";
            stage = "internal-normalized";
          };
        };
      };
    };

    output = {
      link = {
        id = "link::<siteName>::<linkName>";
      };
      node = {
        forwarding = {
          functions = "explicit";
          traversal = {
            participates = "explicit";
            chainIndex = "explicit";
            incoming = "explicit";
            outgoing = "explicit";
          };
          responsibilities = {
            accessTermination = "explicit";
            policyEnforcement = "explicit";
            transitForwarding = "explicit";
          };
          authority = {
            attachedPrefixRouting = "explicit";
            transitRouting = "explicit";
            upstreamSelection = "explicit";
          };
        };
        egress = {
          authority = "explicit";
          upstreamSelection = "explicit";
          exitEligible = "explicit";
          wanInterfaces = "explicit";
          uplinkNames = "explicit";
        };
      };
      route = {
        intent = {
          field = "intent.kind";
          values = [
            "connected-reachability"
            "internal-reachability"
            "overlay-reachability"
            "uplink-learned-reachability"
            "default-reachability"
          ];
        };
      };
      transit = {
        adjacencies = {
          idField = "id";
          endpoint = {
            unit = "required";
            local = {
              ipv4 = "required";
              ipv6 = "optional";
            };
          };
        };
        ordering = {
          field = "enterprise.<enterprise>.site.<site>.transit.ordering";
          shape = "stable-link-ids";
          source = "resolved internal transit node-pair ordering against realized p2p links";
        };
      };
    };
  };

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
