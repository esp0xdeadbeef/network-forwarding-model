{ lib }:

let
  assert_ = cond: msg: if cond then true else throw msg;

  isContainerAttr =
    name: v:
    builtins.isAttrs v
    && !(lib.elem name [
      "role"
      "networks"
      "interfaces"
    ]);

  containerNamesOf = node: builtins.attrNames (lib.filterAttrs isContainerAttr node);

  ifaceNames =
    x:
    if builtins.isAttrs x && x ? interfaces && builtins.isAttrs x.interfaces then
      builtins.attrNames x.interfaces
    else
      [ ];

in
{
  check =
    { site }:
    let
      siteName = toString (site.siteName or "<unknown-site>");
      nodes = site.nodes or { };

      _ = lib.forEach (builtins.attrNames nodes) (
        nodeName:
        let
          node = nodes.${nodeName};
          role = node.role or null;
        in
        if role != "core" then
          true
        else
          let
            containers = containerNamesOf node;

            step =
              acc: cname:
              let
                ifs = ifaceNames (node.${cname} or { });

                addOne =
                  acc2: lname:
                  if acc2 ? "${lname}" then
                    throw ''
                      invariants(core-containers-unique-interfaces):

                      core container interface duplication detected

                        site: ${siteName}
                        node: ${nodeName}
                        link: ${lname}

                      link present in multiple core containers:

                        ${acc2.${lname}}
                        ${cname}
                    ''
                  else
                    acc2 // { "${lname}" = cname; };
              in
              builtins.foldl' addOne acc ifs;

            seen = builtins.foldl' step { } containers;
          in
          builtins.deepSeq seen true
      );
    in
    true;
}
