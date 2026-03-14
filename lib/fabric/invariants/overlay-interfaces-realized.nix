{ lib }:

let
  assert_ = cond: msg: if cond then true else throw msg;

  normalizeOverlay =
    x:
    if builtins.isString x then
      {
        name = toString x;
      }
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

  expectedInterfaceName = overlayName: "overlay-${toString overlayName}";

in
{
  check =
    { site }:
    let
      siteName = toString (site.siteName or "<unknown-site>");
      nodes = site.nodes or { };
      overlays = overlayItemsFrom site;

      checkOverlay =
        overlay:
        let
          overlayName = toString overlay.name;
          ifName = expectedInterfaceName overlayName;
          targets = lib.unique (targetNamesFrom overlay);

          _haveTargets = assert_ (targets != [ ]) ''
            invariants(overlay-interfaces-realized):

            overlay is missing terminateOn target(s)

              site: ${siteName}
              overlay: ${overlayName}
          '';

          _targetsExist = lib.forEach targets (
            nodeName:
            assert_ (nodes ? "${nodeName}") ''
              invariants(overlay-interfaces-realized):

              overlay terminateOn target references unknown node

                site: ${siteName}
                overlay: ${overlayName}
                node: ${nodeName}
            ''
          );

          _interfacesExist = lib.forEach targets (
            nodeName:
            let
              iface = ((nodes.${nodeName}.interfaces or { }).${ifName} or null);
            in
            builtins.seq
              (assert_ (iface != null) ''
                invariants(overlay-interfaces-realized):

                overlay transport interface was not materialized

                  site: ${siteName}
                  overlay: ${overlayName}
                  node: ${nodeName}
                  expectedInterface: ${ifName}
              '')
              (
                assert_ ((iface.overlay or null) == overlayName) ''
                  invariants(overlay-interfaces-realized):

                  overlay transport interface has wrong overlay marker

                    site: ${siteName}
                    overlay: ${overlayName}
                    node: ${nodeName}
                    interface: ${ifName}
                    found: ${toString (iface.overlay or "<missing>")}
                ''
              )
          );
        in
        builtins.seq _haveTargets (builtins.deepSeq _targetsExist (builtins.deepSeq _interfacesExist true));

      _ = lib.forEach overlays checkOverlay;
    in
    builtins.deepSeq _ true;
}
