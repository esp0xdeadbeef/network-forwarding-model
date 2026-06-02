{ lib, self ? { outPath = ./.; }, ... }:

let
  helpers = import (self.outPath + "/implementation/lib/routing/static-helpers.nix") { inherit lib self; };
  link = import (self.outPath + "/implementation/lib/topology/link-utils.nix") { inherit lib self; };
  overlayScope = import ./overlay-scope.nix { inherit lib; };
  nodeFacts = import ./remote-prefixes/node-facts.nix { inherit lib; };
  laneMetadata = import (self.outPath + "/implementation/lib/routing/lane-metadata.nix") {
    inherit lib self;
  };
  inherit (laneMetadata)
    laneAccessNodeName
    laneUplinkName
    ;

  cleanName = value: if value == null then "" else toString value;

  asList =
    value:
    if value == null then [ ] else if builtins.isList value then value else [ value ];

in
rec {
  buildFacts =
    topo:
    let
      links = topo.links or { };
      nodes = topo.nodes or { };
      nodeNames = helpers.allNodeNames topo;
      linkNames = builtins.attrNames links;
      tenantOwnerEntries = builtins.attrValues (topo.tenantPrefixOwners or { });
      overlayScopeFacts = overlayScope.build topo tenantOwnerEntries;
      overlayPolicyAllowedNodes = overlayScopeFacts.policyAllowedNodes;
      overlayAllowedNodes = overlayScopeFacts.attachmentAllowedNodes;

      addUnique = acc: name: value:
        acc // { "${name}" = lib.unique ((acc.${name} or [ ]) ++ [ value ]); };

      linkFacts =
        builtins.foldl'
          (
            acc: linkName:
              let
                linkObj = links.${linkName};
                uplinkName = laneUplinkName linkObj;
                accessNodeName = laneAccessNodeName linkObj;
                members = link.membersOf linkObj;
                accWithNodeUplinks =
                  if accessNodeName != null || uplinkName == null then
                    acc
                  else
                    builtins.foldl'
                      (
                        nodeAcc: member: nodeAcc // { uplinksByNode = addUnique nodeAcc.uplinksByNode member uplinkName; }
                      )
                      acc
                      members;
              in
              if accessNodeName == null || uplinkName == null then
                accWithNodeUplinks
              else
                accWithNodeUplinks // {
                  uplinksByAccess = addUnique accWithNodeUplinks.uplinksByAccess accessNodeName uplinkName;
                }
          )
          { uplinksByNode = { }; uplinksByAccess = { }; }
          linkNames;

      accessUnitByTenant =
        builtins.foldl'
          (
            acc: attachment:
              if !(builtins.isAttrs attachment) || (attachment.kind or null) != "tenant" then
                acc
              else
                let
                  tenantName = cleanName (attachment.name or null);
                  unitName = cleanName (attachment.unit or null);
                in
                if tenantName == "" || unitName == "" then acc else acc // { "${tenantName}" = unitName; }
          )
          { }
          (topo.attachments or [ ]);

      endpointTenantByName =
        builtins.foldl'
          (
            acc: endpoint:
              if !(builtins.isAttrs endpoint) then
                acc
              else
                let
                  endpointName = cleanName (endpoint.name or null);
                  tenantName = cleanName (endpoint.tenant or null);
                in
                if endpointName == "" || tenantName == "" then acc else acc // { "${endpointName}" = tenantName; }
          )
          { }
          (topo.ownership.endpoints or [ ]);

      serviceProviderAccessUnits =
        serviceName:
        let
          services =
            if (topo.communicationContract or { }) ? services then
              topo.communicationContract.services
            else
              topo.services or [ ];
          matches =
            lib.filter
              (service: builtins.isAttrs service && cleanName (service.name or null) == serviceName)
              services;
          providers =
            lib.concatMap
              (service: map (provider: cleanName provider) (asList (service.providers or [ ])))
              matches;
        in
        lib.unique (
          lib.filter (unitName: unitName != "") (
            map
              (
                provider:
                  let
                    tenantName = endpointTenantByName.${provider} or "";
                  in
                  if tenantName == "" then "" else accessUnitByTenant.${tenantName} or ""
              )
              providers
          )
        );

      sourceExternalUplinks =
        source:
        if (source.kind or null) != "external" then
          [ ]
        else if builtins.isList (source.uplinks or null) then
          map (uplink: cleanName uplink) source.uplinks
        else if (source.name or null) != null then
          [ (cleanName source.name) ]
        else
          [ ];

      accessUnitsInPath =
        path:
        lib.unique (
          lib.filter
            (nodeName: ((nodes.${nodeName} or { }).role or null) == "access")
            (map (nodeName: cleanName nodeName) path)
        );

      dnsServiceRouteScopes =
        path:
        if
          !(builtins.isAttrs path)
          || (path.action or null) != "allow"
          || (path.trafficType or null) != "dns"
          || ((path.destination or { }).kind or null) != "service"
        then
          [ ]
        else
          let
            serviceName = cleanName ((path.destination or { }).name or null);
            providerAccessUnits = serviceProviderAccessUnits serviceName;
            uplinks = sourceExternalUplinks (path.source or { });
            alternatives = path.nodePathAlternatives or [ (path.nodePath or [ ]) ];
            requesterAccessUnits =
              lib.filter
                (accessUnit: !(builtins.elem accessUnit providerAccessUnits))
                (lib.concatMap accessUnitsInPath alternatives);
          in
          if serviceName == "" || providerAccessUnits == [ ] || requesterAccessUnits == [ ] || uplinks == [ ] then
            [ ]
          else
            lib.concatMap
              (
                owner:
                  lib.concatMap
                    (
                      access:
                        map
                          (uplink: {
                            inherit access owner serviceName uplink;
                          })
                          uplinks
                    )
                    requesterAccessUnits
              )
              providerAccessUnits;

      serviceRouteScopesByOwner =
        builtins.foldl'
          (
            acc: scope:
              acc // {
                "${scope.owner}" = lib.unique (
                  (acc.${scope.owner} or [ ])
                  ++ [
                    (builtins.removeAttrs scope [ "owner" ])
                  ]
                );
              }
          )
          { }
          (lib.concatMap dnsServiceRouteScopes (topo.trafficPaths or [ ]));

      p2pByOwner = builtins.listToAttrs (
        map
          (owner: {
            name = owner;
            value =
              let
                prefixes = builtins.attrValues (helpers.prefixSetFromP2pIfaces nodes.${owner});
                concreteEntries = map
                  (
                    x:
                    x
                    // {
                      owner = owner;
                      kind = "p2p";
                    }
                  )
                  prefixes;
              in
              concreteEntries;
          })
          nodeNames
      );

      p2pEntries = lib.concatMap (owner: p2pByOwner.${owner} or [ ]) nodeNames;

      overlayRouteEntries = lib.concatMap
        (
          overlay:
          let
            owners = overlay.terminateOn or [ ];
            v4s = map (r: {
              family = 4;
              dst = r.dst or null;
              peerSite = r.peerSite or (overlay.peerSite or null);
              overlay = r.overlay or (overlay.overlay or null);
            }) (overlay.routes4 or [ ]);
            v6s = map (r: {
              family = 6;
              dst = r.dst or null;
              peerSite = r.peerSite or (overlay.peerSite or null);
              overlay = r.overlay or (overlay.overlay or null);
            }) (overlay.routes6 or [ ]);
            prefixes = lib.filter (e: e.dst != null) (v4s ++ v6s);
          in
          lib.concatMap
            (
              owner:
              map
                (
                  e:
                  e
                  // {
                    owner = owner;
                    kind = "overlay";
                    overlay = e.overlay or (overlay.overlay or null);
                    peerSite = e.peerSite or (overlay.peerSite or null);
                  }
                )
                prefixes
            )
            owners
        )
        (builtins.attrValues (topo.overlayReachability or { }));

      ownConnectedPrefixSetByNode = builtins.listToAttrs (
        map
          (nodeName: {
            name = nodeName;
            value = helpers.ownConnectedPrefixes nodes.${nodeName};
          })
          nodeNames
      );

      remoteByNode =
        nodeFacts.build {
          inherit
            linkFacts
            nodeNames
            nodes
            overlayAllowedNodes
            overlayPolicyAllowedNodes
            overlayRouteEntries
            p2pEntries
            tenantOwnerEntries
            ;
        };
    in
    {
      inherit
        nodeNames
        ownConnectedPrefixSetByNode
        p2pByOwner
        p2pEntries
        overlayRouteEntries
        remoteByNode
        ;
      inherit tenantOwnerEntries;
      inherit overlayPolicyAllowedNodes;
      overlayEntries = builtins.attrValues (topo.overlayReachability or { });
      inherit overlayAllowedNodes;
      inherit (linkFacts) uplinksByNode uplinksByAccess;
      inherit serviceRouteScopesByOwner;
    };

  byKindForNodeWithFacts =
    facts: _: nodeName:
      facts.remoteByNode.${nodeName} or {
        tenant = [ ];
        overlay = [ ];
        p2p = [ ];
      };
}
