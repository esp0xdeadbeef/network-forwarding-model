{ lib }:

let
  common = import ./common.nix { inherit lib; };

  ifaceCount =
    x:
    if builtins.isAttrs x && x ? interfaces && builtins.isAttrs x.interfaces then
      builtins.length (builtins.attrNames x.interfaces)
    else
      0;

in
{
  check =
    { site }:
    if !(builtins.isAttrs (site.links or null)) then
      true
    else
      let
        siteName = toString (site.siteName or "<unknown-site>");
        nodes = site.nodes or { };

        checkAccessNode =
          nodeName:
          let
            node = nodes.${nodeName};
            n = ifaceCount node;
          in
          if (node.role or null) != "access" then
            true
          else
            common.assert_ (n >= 1) ''
              invariants(node-role-interface-degree):

              access node must have at least 1 interface

                site: ${siteName}
                node: ${nodeName}

                found: ${toString n}
                expected: >= 1
            '';
      in
      builtins.deepSeq (lib.forEach (builtins.attrNames nodes) checkAccessNode) true;
}
