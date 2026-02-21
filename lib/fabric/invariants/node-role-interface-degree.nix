{ lib }:

let
  assert_ = cond: msg: if cond then true else throw msg;

  isBoxAttr =
    name: v:
    builtins.isAttrs v
    && !(lib.elem name [
      "role"
      "networks"
      "interfaces"
    ]);

  boxesOf = node: builtins.attrNames (lib.filterAttrs isBoxAttr node);

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
          in
          if (node.role or null) != "access" then
            true
          else
            let
              boxes = boxesOf node;

              checkBox =
                b:
                let
                  box = node.${b} or { };
                  n = ifaceCount box;
                in
                assert_ (n == 2) ''
                  invariants(node-role-interface-degree):

                  access box must have exactly 2 interfaces

                    site: ${siteName}
                    node: ${nodeName}
                    box:  ${nodeName}.${b}

                    found: ${toString n}
                    expected: 2
                '';
            in
            builtins.deepSeq (lib.forEach boxes checkBox) true;

      in
      builtins.deepSeq (lib.forEach (builtins.attrNames nodes) checkAccessNode) true;
}
