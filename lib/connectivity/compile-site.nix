# lib/compile-site.nix
{ lib }:

site:

let
  isBoxAttr =
    name: v:
    builtins.isAttrs v
    && !(lib.elem name [
      "role"
      "networks"
      "interfaces"
    ]);

  boxesOf = node: builtins.attrNames (lib.filterAttrs isBoxAttr node);

  expandPair =
    a: b:
    let
      na = site.nodes.${a};
      nb = site.nodes.${b};

      expandSide =
        nodeName: node:
        let
          boxes = boxesOf node;
        in
        if boxes == [ ] then [ nodeName ] else map (bx: "${nodeName}.${bx}") boxes;

      lefts = expandSide a na;
      rights = expandSide b nb;
    in
    lib.concatMap
      (l: map (r: [ l r ]) rights)
      lefts;

  expandedLinks =
    lib.concatMap
      (pair: expandPair (builtins.elemAt pair 0) (builtins.elemAt pair 1))
      (site.links or [ ]);

  emptyNode =
    n:
    let
      boxes = boxesOf n;
    in
    n
    // { interfaces = { }; }
    // lib.genAttrs boxes (_: { interfaces = { }; });

  nodes0 = lib.mapAttrs (_: emptyNode) (site.nodes or { });

  splitName =
    name:
    let
      parts = lib.splitString "." name;
    in
    if builtins.length parts == 1 then
      { node = name; box = null; }
    else
      { node = builtins.elemAt parts 0; box = builtins.elemAt parts 1; };

  linkNameOf =
    idx: pair:
    let
      a = builtins.elemAt pair 0;
      b = builtins.elemAt pair 1;
    in
    "link-${toString idx}-${a}-${b}";

  attachOneLink =
    nodesAcc: idx: pair:
    let
      a = builtins.elemAt pair 0;
      b = builtins.elemAt pair 1;

      name = linkNameOf idx pair;

      addEndpoint =
        nodesA: ep: peer:
        let
          parsed = splitName ep;
          node = parsed.node;
          box = parsed.box;

          iface = {
            peer = peer;
            kind = "adjacency";
          };
        in
        if box == null then
          nodesA // {
            ${node} = nodesA.${node} // {
              interfaces =
                (nodesA.${node}.interfaces or { })
                // { ${name} = iface; };
            };
          }
        else
          nodesA // {
            ${node} = nodesA.${node} // {
              ${box} = nodesA.${node}.${box} // {
                interfaces =
                  (nodesA.${node}.${box}.interfaces or { })
                  // { ${name} = iface; };
              };
            };
          };
    in
    addEndpoint
      (addEndpoint nodesAcc a b)
      b
      a;

  nodesWithAdj =
    builtins.foldl'
      (acc:
        pair:
        let
          idx = acc.__idx or 0;
          nodesOnly = builtins.removeAttrs acc [ "__idx" ];
          nextNodes = attachOneLink nodesOnly idx pair;
        in
        nextNodes // { __idx = idx + 1; })
      (nodes0 // { __idx = 0; })
      expandedLinks;

  nodesFinal = builtins.removeAttrs nodesWithAdj [ "__idx" ];

  addAccessLan =
    lib.mapAttrs
      (nodeName: node:
        if (node.role or null) != "access" then
          node
        else
          let
            boxes = boxesOf node;

            addOne =
              acc: boxName:
              let
                box = acc.${boxName} or { };
                ifs = box.interfaces or { };
              in
              acc // {
                ${boxName} = box // {
                  interfaces =
                    ifs
                    // {
                      "lan-${boxName}" = {
                        kind = "lan";
                        carrier = "lan";
                      };
                    };
                };
              };
          in
          builtins.foldl' addOne node boxes)
      nodesFinal;

in
{
  nodes = addAccessLan;
  links = expandedLinks;
}
