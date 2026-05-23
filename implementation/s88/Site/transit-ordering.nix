{ lib, self ? { outPath = ./.; }, ... }:

let
  roleStages = import (self.outPath + "/implementation/lib/fabric/transit-role-stages.nix") { inherit lib self; };

  uniqueNodeNames =
    pairs:
    lib.sort (a: b: a < b) (
      lib.unique (
        lib.concatMap
          (
            pair: if builtins.isList pair && builtins.length pair == 2 then map toString pair else [ ]
          )
          pairs
      )
    );

  roleCatalogFrom =
    { siteName
    , pairs
    , roleFromInput
    ,
    }:
    let
      nodeNames = uniqueNodeNames pairs;
    in
    builtins.listToAttrs (
      map
        (
          nodeName:
          let
            role = roleFromInput nodeName;
          in
          if role == null || role == "" then
            throw ''
              network-forwarding-model: transit ordering references node without explicit role

              site: ${siteName}
              node: ${toString nodeName}
            ''
          else
            {
              name = toString nodeName;
              value = toString role;
            }
        )
        nodeNames
    );

  hasRole = roles: wanted: lib.any (nodeName: roles.${nodeName} == wanted) (builtins.attrNames roles);

  nextRoleOf =
    roles: role:
    roleStages.nextTransitRole {
      inherit role;
      hasDownstreamSelector = hasRole roles "downstream-selector";
      hasUpstreamSelector = hasRole roles "upstream-selector";
    };

  canonicalizeOne =
    { siteName
    , site
    , roles
    , pair
    ,
    }:
    let
      firstEndpoint = toString (builtins.elemAt pair 0);
      secondEndpoint = toString (builtins.elemAt pair 1);

      firstEndpointRole = roles.${firstEndpoint};
      secondEndpointRole = roles.${secondEndpoint};

      firstEndpointRank = roleStages.transitRank firstEndpointRole;
      secondEndpointRank = roleStages.transitRank secondEndpointRole;

      oriented =
        if firstEndpointRank < secondEndpointRank then
          [
            firstEndpoint
            secondEndpoint
          ]
        else if secondEndpointRank < firstEndpointRank then
          [
            secondEndpoint
            firstEndpoint
          ]
        else
          throw ''
            network-forwarding-model: transit ordering cannot connect nodes in the same canonical stage

            site: ${siteName}
            left:  ${firstEndpoint} (${firstEndpointRole})
            right: ${secondEndpoint} (${secondEndpointRole})
          '';

      sourceNode = builtins.elemAt oriented 0;
      destinationNode = builtins.elemAt oriented 1;

      sourceRole = roles.${sourceNode};
      destinationRole = roles.${destinationNode};
      expectedDestinationRole = nextRoleOf roles sourceRole;

      overlayItems =
        let
          overlays = ((site.transport or { }).overlays or [ ]);
        in
        if builtins.isList overlays then
          lib.filter (ov: ov != null && builtins.isAttrs ov) overlays
        else if builtins.isAttrs overlays then
          lib.mapAttrsToList (name: ov: ov // { inherit name; }) overlays
        else
          [ ];

      attachmentsForNode =
        nodeName:
        (site.topology.nodes.${nodeName}.attachments or [ ])
        ++ lib.filter (att: toString (att.unit or "") == nodeName) (site.attachments or [ ]);

      nodeHasUnderlayAccess =
        nodeName: selector:
        (selector.kind or null) == "tenant"
        && lib.any
          (
            att:
            (att.kind or null) == "tenant"
            && toString (att.name or "") == toString selector.name
          )
          (attachmentsForNode nodeName);

      overlayAttachments = site.overlayAttachments or { };

      allowedByCompilerAttachment =
        lib.any
          (
            overlayName:
            let
              attachment = overlayAttachments.${overlayName};
              accessNodes = map toString (attachment.accessNodes or [ ]);
              coreNodes = map toString (attachment.terminatesOn or [ ]);
            in
            lib.elem firstEndpoint accessNodes && lib.elem secondEndpoint coreNodes
            || lib.elem secondEndpoint accessNodes && lib.elem firstEndpoint coreNodes
          )
          (builtins.attrNames overlayAttachments);

      allowedByIntentOverlay =
        lib.any
          (
            overlay:
            let
              terminateOn = toString (overlay.terminateOn or "");
              underlayAccess = overlay.underlayAccess or null;
            in
            underlayAccess != null
            && (
              (
                firstEndpoint == terminateOn
                && nodeHasUnderlayAccess secondEndpoint underlayAccess
              )
              || (
                secondEndpoint == terminateOn
                && nodeHasUnderlayAccess firstEndpoint underlayAccess
              )
            )
          )
          overlayItems;

      isExplicitOverlayUnderlayAccess =
        (
          (firstEndpointRole == "core" && secondEndpointRole == "access")
          || (firstEndpointRole == "access" && secondEndpointRole == "core")
        )
        && (allowedByCompilerAttachment || allowedByIntentOverlay);
    in
    if expectedDestinationRole == null then
      throw ''
        network-forwarding-model: canonical transit ordering cannot originate from terminal stage

        site: ${siteName}
        node: ${sourceNode}
        role: ${sourceRole}
      ''
    else if destinationRole != expectedDestinationRole && !isExplicitOverlayUnderlayAccess then
      throw ''
        network-forwarding-model: transit ordering violates canonical stage adjacency

        site: ${siteName}
        pair: ${sourceNode} -> ${destinationNode}

        sourceRole: ${sourceRole}
        destinationRole: ${destinationRole}
        expectedDestinationRole: ${expectedDestinationRole}
      ''
    else
      oriented;

  pairSortKey =
    roles: pair:
    let
      sourceNode = toString (builtins.elemAt pair 0);
      destinationNode = toString (builtins.elemAt pair 1);
    in
    "${toString (roleStages.transitRank roles.${sourceNode})}|${sourceNode}|${destinationNode}";
in
{
  canonicalize =
    { siteName
    , site ? { }
    , pairs
    , roleFromInput
    ,
    }:
    let
      roles = roleCatalogFrom {
        inherit siteName pairs roleFromInput;
      };

      orientedPairs = map
        (
          pair:
          canonicalizeOne {
            inherit siteName site roles pair;
          }
        )
        pairs;
    in
    lib.sort (x: y: (pairSortKey roles x) < (pairSortKey roles y)) orientedPairs;
}
