{ lib, self ? { outPath = ./.; }, ... }:

let
  routeFields = import (self.outPath + "/implementation/lib/routing/loopbacks/route-fields.nix") { inherit lib self; };

in
node: linkName: add4: add6:
if linkName == null then
  node
else
  let
    ifs = node.interfaces or { };
    cur = if ifs ? "${linkName}" then ifs.${linkName} else null;
    curRoutes =
      if cur == null then
        {
          ipv4 = [ ];
          ipv6 = [ ];
        }
      else
        routeFields.ifaceRoutes cur;
  in
  if cur == null then
    node
  else
    node
    // {
      interfaces = ifs // {
        "${linkName}" = cur // {
          routes = {
            ipv4 = curRoutes.ipv4 ++ (if add4 == null then [ ] else add4);
            ipv6 = curRoutes.ipv6 ++ (if add6 == null then [ ] else add6);
          };
        };
      };
    }
