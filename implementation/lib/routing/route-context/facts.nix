{ lib, self ? { outPath = ./.; }, ... }:

let
  helpers = import (self.outPath + "/implementation/lib/routing/static-helpers.nix") { inherit lib self; };
  trace = import (self.outPath + "/lib/trace.nix") { };

  loopbackEntriesFor =
    nodes: nodeName:
    let
      loopback = nodes.${nodeName}.loopback or { };
      entry =
        family: raw:
        if raw == null then
          [ ]
        else
          [
            {
              name = "${toString family}|${helpers.stripMask raw}";
              value = nodeName;
            }
          ];
    in
    (entry 4 (loopback.ipv4 or null)) ++ (entry 6 (loopback.ipv6 or null));

  overlayUplinkNames =
    topo: links:
    let
      overlayReachabilityNames = builtins.attrNames (topo.overlayReachability or { });
      linkOverlayNames = lib.filter (name: name != null) (
        map (linkName: (links.${linkName}.overlay or null)) (builtins.attrNames links)
      );
    in
    lib.listToAttrs (
      map (name: {
        inherit name;
        value = true;
      }) (lib.unique (overlayReachabilityNames ++ linkOverlayNames))
    );

  uplinkHasDefaultSet =
    nodes: links:
    let
      addDefault = acc: uplinkName: acc // { "${uplinkName}" = true; };
      addNode = acc: nodeName:
        builtins.foldl' (
          nodeAcc: uplinkName:
          let
            uplink = ((nodes.${nodeName} or { }).uplinks or { }).${uplinkName} or { };
          in
          if builtins.elem helpers.default4 (uplink.ipv4 or [ ]) || builtins.elem helpers.default6 (uplink.ipv6 or [ ]) then
            addDefault nodeAcc uplinkName
          else
            nodeAcc
        ) acc (builtins.attrNames ((nodes.${nodeName} or { }).uplinks or { }));
      endpointHasDefault =
        ep:
        let
          e = ep.interfaceData or ep;
        in
        builtins.elem helpers.default4 (e.uplinkRoutes4 or [ ])
        || builtins.elem helpers.default6 (e.uplinkRoutes6 or [ ]);
      addLink = acc: linkName:
        let
          link = links.${linkName};
          uplinkName = link.upstream or link.uplink or null;
        in
        if uplinkName != null && builtins.any endpointHasDefault (builtins.attrValues (link.endpoints or { })) then
          addDefault acc uplinkName
        else
          acc;
    in
    builtins.foldl' addLink (builtins.foldl' addNode { } (builtins.attrNames nodes)) (builtins.attrNames links);

  uplinkCoreNamesByUplink =
    nodes: links: uplinkCores:
    let
      addCoreUplink = acc: uplinkName: coreName:
        acc // { "${uplinkName}" = lib.unique ((acc.${uplinkName} or [ ]) ++ [ coreName ]); };
      addNodeUplinks = acc: coreName:
        builtins.foldl' (
          nodeAcc: uplinkName: addCoreUplink nodeAcc uplinkName coreName
        ) acc (builtins.attrNames (((nodes.${coreName} or { }).uplinks or { })));
      addLinkUplinks = acc: linkName:
        let
          link = links.${linkName};
          members = if builtins.isList (link.members or null) then map toString link.members else [ ];
          uplinks = if builtins.isList (link.uplinks or null) then map toString link.uplinks else [ ];
          memberCores = lib.filter (member: builtins.elem member uplinkCores) members;
        in
        builtins.foldl' (
          linkAcc: uplinkName:
          builtins.foldl' (
            coreAcc: coreName: addCoreUplink coreAcc uplinkName coreName
          ) linkAcc memberCores
        ) acc uplinks;
    in
    builtins.foldl' addLinkUplinks (builtins.foldl' addNodeUplinks { } uplinkCores) (builtins.attrNames links);
in
{
  build =
    topo:
    let
      nodes = topo.nodes or { };
      links = topo.links or { };
      overlayUplinkNameSet = overlayUplinkNames topo links;
      nonOverlayUplinkNames =
        lib.filter (uplinkName: !(builtins.hasAttr uplinkName overlayUplinkNameSet)) (topo.uplinkNames or [ ]);
      uplinkCores = helpers.uplinkCores topo;
    in
    trace.emit "routing:facts:nodes=${toString (builtins.length (builtins.attrNames nodes))}:links=${toString (builtins.length (builtins.attrNames links))}" {
      loopbackOwnerByKey = builtins.listToAttrs (
        lib.concatMap (loopbackEntriesFor nodes) (builtins.attrNames nodes)
      );
      inherit overlayUplinkNameSet nonOverlayUplinkNames uplinkCores;
      uplinkCoreSet = lib.listToAttrs (map (name: {
        inherit name;
        value = true;
      }) uplinkCores);
      uplinkHasDefaultSet = uplinkHasDefaultSet nodes links;
      uplinkCoreNamesByUplink = uplinkCoreNamesByUplink nodes links uplinkCores;
      defaultReachabilityUplinkNames =
        if nonOverlayUplinkNames != [ ] then nonOverlayUplinkNames else topo.uplinkNames or [ ];
    };
}
