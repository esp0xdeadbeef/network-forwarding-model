{ lib, ... }:

let
  strip =
    a:
    let
      s = toString a;
      parts = lib.splitString "/" s;
    in
    if builtins.length parts > 0 then builtins.elemAt parts 0 else s;

in
{
  inherit strip;

  hostDst4 = cidr: "${strip cidr}/32";
  hostDst6 = cidr: "${strip cidr}/128";

  ifaceRoutes =
    iface:
    if iface ? routes && builtins.isAttrs iface.routes then
      {
        ipv4 = iface.routes.ipv4 or [ ];
        ipv6 = iface.routes.ipv6 or [ ];
      }
    else
      {
        ipv4 = iface.routes4 or [ ];
        ipv6 = iface.routes6 or [ ];
      };
}
