{ lib, ... }:

let
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
topoRaw:
let
  transport = topoRaw.transport or { };
  overlays0 = transport.overlays or [ ];

  items =
    if builtins.isList overlays0 then
      lib.filter (x: x != null) (map normalizeOverlay overlays0)
    else if builtins.isAttrs overlays0 then
      lib.filter (x: x != null) (
        lib.mapAttrsToList (name: v: normalizeOverlay (v // { inherit name; })) overlays0
      )
    else
      [ ];

in
{
  reachability = topoRaw.overlayReachability or { };

  forNode =
    nodeName:
    lib.filter (overlay: lib.elem nodeName (lib.unique (targetNamesFrom overlay))) items;
}
