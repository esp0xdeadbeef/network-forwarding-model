{ lib, ... }:

{
  uplinkName =
    linkName:
    let
      marker = "--uplink-";
      parts = lib.splitString marker (toString linkName);
    in
    if builtins.length parts < 2 then null else builtins.elemAt parts ((builtins.length parts) - 1);

  accessNodeName =
    linkName:
    let
      marker = "--access-";
      parts = lib.splitString marker (toString linkName);
      lastPart =
        if builtins.length parts < 2 then null else builtins.elemAt parts ((builtins.length parts) - 1);
      segments = if lastPart == null then [ ] else lib.splitString "--uplink-" lastPart;
    in
    if segments == [ ] then null else builtins.elemAt segments 0;
}
