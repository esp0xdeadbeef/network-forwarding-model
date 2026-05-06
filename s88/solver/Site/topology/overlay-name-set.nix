{ lib }:

site:

let
  overlays = ((site.transport or { }).overlays or [ ]);
  overlayNames =
    if builtins.isList overlays then
      map (
        overlay:
        if builtins.isAttrs overlay && (overlay.name or null) != null then
          toString overlay.name
        else
          toString overlay
      ) overlays
    else if builtins.isAttrs overlays then
      builtins.attrNames overlays
    else
      [ ];
in
lib.listToAttrs (map (name: {
  inherit name;
  value = true;
}) overlayNames)
