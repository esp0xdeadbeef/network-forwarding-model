{ lib }:

let
  isNetworkAttr =
    {
      extraExcluded ? [ ],
    }:
    name: v:
    builtins.isAttrs v
    && (v ? ipv4 || v ? ipv6)
    && !(lib.elem name (
      [
        "role"
        "interfaces"
        "networks"
      ]
      ++ extraExcluded
    ));

  networksOfRaw =
    {
      extraExcluded ? [ ],
    }:
    node:
    if node ? networks then
      node.networks
    else
      lib.filterAttrs (isNetworkAttr { inherit extraExcluded; }) node;

  networksOfNode =
    {
      extraExcluded ? [
        "containers"
        "uplinks"
      ],
    }:
    node:
    if node ? networks && builtins.isAttrs node.networks then
      let
        nets = node.networks;
      in
      if nets ? ipv4 || nets ? ipv6 then { default = nets; } else nets
    else
      lib.filterAttrs (isNetworkAttr { inherit extraExcluded; }) node;
in
{
  inherit
    isNetworkAttr
    networksOfRaw
    networksOfNode
    ;
}
