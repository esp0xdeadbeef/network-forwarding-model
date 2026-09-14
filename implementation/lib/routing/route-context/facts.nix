{
  lib,
  self ? {
    outPath = ./.;
  },
  ...
}:

let
  helpers = import (self.outPath + "/implementation/lib/routing/static-helpers.nix") {
    inherit lib self;
  };
  defaultPresence = import ./default-presence.nix { inherit lib helpers; };
  inherit (defaultPresence)
    uplinkHasDefaultSet
    uplinkHasDefault4Set
    uplinkHasDefault6Set
    overlayMembersFor
    ;
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

  # An overlay is not a default in any family by itself: overlay reachability
  # carries peer prefixes (overlayReachability.<name>.routes4/routes6), never a
  # 0.0.0.0/0 or ::/0. Treating "is an overlay" as "has an executable default"
  # in both families admits an egress into a family's multipath member set even
  # when the overlay carries no prefix in that family (FS-315, SMS-010).
  uplinkCoreNamesByUplink =
    nodes: links: uplinkCores:
    let
      addCoreUplink =
        acc: uplinkName: coreName:
        acc // { "${uplinkName}" = lib.unique ((acc.${uplinkName} or [ ]) ++ [ coreName ]); };
      addNodeUplinks =
        acc: coreName:
        builtins.foldl' (nodeAcc: uplinkName: addCoreUplink nodeAcc uplinkName coreName) acc (
          builtins.attrNames (((nodes.${coreName} or { }).uplinks or { }))
        );
      addLinkUplinks =
        acc: linkName:
        let
          link = links.${linkName};
          members = if builtins.isList (link.members or null) then map toString link.members else [ ];
          uplinks = if builtins.isList (link.uplinks or null) then map toString link.uplinks else [ ];
          memberCores = lib.filter (member: builtins.elem member uplinkCores) members;
        in
        builtins.foldl' (
          linkAcc: uplinkName:
          builtins.foldl' (coreAcc: coreName: addCoreUplink coreAcc uplinkName coreName) linkAcc memberCores
        ) acc uplinks;
    in
    builtins.foldl' addLinkUplinks (builtins.foldl' addNodeUplinks { } uplinkCores) (
      builtins.attrNames links
    );
in
{
  build =
    topo:
    let
      nodes = topo.nodes or { };
      links = topo.links or { };
      overlayUplinkNameSet = overlayUplinkNames topo links;
      nonOverlayUplinkNames = lib.filter (
        uplinkName: !(builtins.hasAttr uplinkName overlayUplinkNameSet)
      ) (topo.uplinkNames or [ ]);
      uplinkCores = helpers.uplinkCores topo;
    in
    trace.emit
      "routing:facts:nodes=${toString (builtins.length (builtins.attrNames nodes))}:links=${toString (builtins.length (builtins.attrNames links))}"
      {
        loopbackOwnerByKey = builtins.listToAttrs (
          lib.concatMap (loopbackEntriesFor nodes) (builtins.attrNames nodes)
        );
        inherit overlayUplinkNameSet nonOverlayUplinkNames uplinkCores;
        overlayHasMembers4 = overlayMembersFor topo links 4;
        overlayHasMembers6 = overlayMembersFor topo links 6;
        uplinkCoreSet = lib.listToAttrs (
          map (name: {
            inherit name;
            value = true;
          }) uplinkCores
        );
        uplinkHasDefaultSet = uplinkHasDefaultSet nodes links;
        uplinkHasDefault4Set = uplinkHasDefault4Set nodes links;
        uplinkHasDefault6Set = uplinkHasDefault6Set nodes links;
        uplinkCoreNamesByUplink = uplinkCoreNamesByUplink nodes links uplinkCores;
        defaultReachabilityUplinkNames =
          if nonOverlayUplinkNames != [ ] then nonOverlayUplinkNames else topo.uplinkNames or [ ];
      };
}
