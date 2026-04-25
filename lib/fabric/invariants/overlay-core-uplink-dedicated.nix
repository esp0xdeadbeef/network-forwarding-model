{ lib }:

let
  common = import ./common.nix { inherit lib; };

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

          offenders = lib.filter (
            nodeName:
            let
              uplinks = builtins.attrNames (nodes.${nodeName}.uplinks or { });
            in
            !(lib.elem overlayName uplinks)
          ) coreTargets;
        in
        common.assert_ (offenders == [ ]) ''
          invariants(overlay-core-uplink-dedicated):

          overlay termination on a core requires a dedicated uplink with the same
          name as the overlay. Do not reuse a generic WAN/ISP core name for the
          overlay runtime; model a separate overlay core such as
          <site>-router-core-${overlayName}.

            site: ${siteName}
            overlay: ${overlayName}
            offending core node(s): ${lib.concatStringsSep ", " offenders}
        '';

      _ = lib.forEach overlays checkOverlay;
    in
    builtins.deepSeq _ true;
}
