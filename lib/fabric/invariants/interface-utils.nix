{ lib }:

let
  common = import ./common.nix { inherit lib; };

  ifaceEntriesFrom =
    {
      whereBase,
      ifaces,
      extra ? { },
      families ? [
        {
          attr = "addr4";
          family = "addr4";
        }
        {
          attr = "addr6";
          family = "addr6";
        }
      ],
    }:
    if !(builtins.isAttrs ifaces) then
      [ ]
    else
      lib.concatMap (
        ifName:
        let
          iface = ifaces.${ifName};

          mk =
            spec:
            {
              family = spec.family;
              ip = common.stripMask iface.${spec.attr};
              where = "${whereBase}.${ifName}.${spec.family}";
              ifname = ifName;
            }
            // extra;
        in
        lib.concatMap (
          spec: if iface ? "${spec.attr}" && iface.${spec.attr} != null then [ (mk spec) ] else [ ]
        ) families
      ) (builtins.attrNames ifaces);

  nonEmptyEntries = entries: lib.filter (e: (toString e.ip) != "") entries;
in
{
  inherit ifaceEntriesFrom nonEmptyEntries;
}
