{
  lib,
  self ? {
    outPath = ./.;
  },
  ...
}:

let
  common = import ./common.nix { inherit lib self; };

  normalizeOverlay =
    x:
    if builtins.isString x then
      { name = toString x; }
    else if builtins.isAttrs x && (x.name or null) != null then
      x // { name = toString x.name; }
    else
      null;

  overlayItemsFrom =
    site:
    let
      overlays0 = ((site.transport or { }).overlays or [ ]);
    in
    if builtins.isList overlays0 then
      lib.filter (x: x != null) (map normalizeOverlay overlays0)
    else if builtins.isAttrs overlays0 then
      lib.filter (x: x != null) (
        lib.mapAttrsToList (name: v: normalizeOverlay (v // { inherit name; })) overlays0
      )
    else
      [ ];

  targetNamesFrom =
    x:
    if x == null then
      [ ]
    else if builtins.isString x then
      [ (toString x) ]
    else if builtins.isList x then
      lib.concatMap targetNamesFrom x
    else if builtins.isAttrs x then
      let
        direct = lib.filter (v: v != null) [
          (if (x.unit or null) != null then toString x.unit else null)
          (if (x.node or null) != null then toString x.node else null)
        ];
      in
      if direct != [ ] then
        direct
      else
        lib.concatMap targetNamesFrom (
          lib.filter (v: v != null) [
            (x.terminateOn or null)
            (x.terminatesOn or null)
            (x.terminatedOn or null)
          ]
        )
    else
      [ ];

in
{
  check =
    { site }:
    let
      siteName = toString (site.siteName or "<unknown-site>");
      nodes = site.nodes or { };
      overlays =
        let
          fromIntent = overlayItemsFrom site;
          fromSolved = lib.mapAttrsToList (name: value: {
            inherit name;
            terminateOn = value.terminateOn or [ ];
          }) (site.overlayReachability or { });
        in
        if fromSolved != [ ] then fromSolved else fromIntent;

      checkOverlay =
        overlay:
        let
          overlayName = toString overlay.name;
          targets = lib.unique (targetNamesFrom overlay);
          coreTargets = lib.filter (nodeName: (nodes.${nodeName}.role or null) == "core") targets;

          # FS-260: a core that terminates an overlay is an overlay endpoint. Its
          # reachability and egress are the modeled overlay relation (FS-460/470),
          # so it is NOT required to declare a local uplink. What is forbidden is
          # reusing the overlay name as a generic WAN/ISP uplink that carries a
          # prefix list, because that models the overlay as a routed core uplink
          # with imported prefixes instead of as the overlay itself.
          offenders = lib.filter (
            nodeName:
            let
              uplink = (nodes.${nodeName}.uplinks or { }).${overlayName} or null;
            in
            # An overlay-named uplink is only an offence when it carries
            # imported prefixes (the retired overlay-as-uplink shape). A core
            # with no overlay-named uplink is a valid overlay endpoint.
            uplink != null
            && (
              (uplink.ipv4 or [ ]) != [ ] || (uplink.ipv6 or [ ]) != [ ] || (uplink.routedPrefixes or [ ]) != [ ]
            )
          ) coreTargets;
        in
        common.assert_ (offenders == [ ]) ''
          invariants(overlay-core-uplink-dedicated):

          an overlay must not be modelled as a routed core uplink with imported
          prefixes. Reachability to the overlay is the modelled overlay or
          remote-egress relation (FS-260/FS-460), not a local uplink that carries
          a prefix list. A core that terminates an overlay needs no local uplink.

            site: ${siteName}
            overlay: ${overlayName}
            offending core node(s): ${lib.concatStringsSep ", " offenders}
        '';

      _ = lib.forEach overlays checkOverlay;
    in
    builtins.deepSeq _ true;
}
