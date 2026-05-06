{ lib, routed }:

let
  uplinkCoreNames =
    if routed ? uplinkCoreNames && builtins.isList routed.uplinkCoreNames then
      routed.uplinkCoreNames
    else
      [ ];

  selector = routed.upstreamSelectorNodeName or null;

  isSelectorToUplink =
    link:
    let
      eps = builtins.attrNames (link.endpoints or { });
    in
    selector != null
    && lib.elem selector eps
    && lib.any (n: lib.elem n uplinkCoreNames) eps;

  links =
    if selector == null then
      { }
    else
      lib.filterAttrs (_: l: isSelectorToUplink l) (routed.links or { });
in
{
  enabled = (builtins.length uplinkCoreNames) > 1;
  count = builtins.length uplinkCoreNames;
  links = links;
}
