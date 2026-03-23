{ lib }:

let
  assert_ = cond: msg: if cond then true else throw msg;

  reservedNodeAttrs = [
    "addressPools"
    "communicationContract"
    "containers"
    "domains"
    "enterprise"
    "interfaces"
    "links"
    "loopback"
    "networks"
    "nodes"
    "role"
    "routingDomain"
    "siteId"
    "siteName"
    "topology"
    "transit"
    "transport"
    "units"
  ];

  isContainerAttr =
    name: v:
    builtins.isAttrs v
    && !(lib.elem name reservedNodeAttrs)
    && (
      builtins.isAttrs (v.interfaces or null)
      || builtins.isAttrs (v.loopback or null)
      || (v.kind or null) == "container"
      || (v.type or null) == "container"
      || (v.container or false) == true
      || v ? networkNamespace
    );

  containersOf =
    node:
    let
      explicit =
        if node ? containers && builtins.isList node.containers then
          map toString node.containers
        else if node ? containers && builtins.isAttrs node.containers then
          builtins.attrNames node.containers
        else
          [ ];

      discovered = lib.filter (name: isContainerAttr name node.${name}) (builtins.attrNames node);
    in
    lib.sort (a: b: a < b) (lib.unique (explicit ++ discovered));

  pairs =
    xs:
    lib.concatMap (
      i:
      let
        a = builtins.elemAt xs i;
      in
      map (
        j:
        let
          b = builtins.elemAt xs j;
        in
        {
          inherit a b;
        }
      ) (lib.range (i + 1) (builtins.length xs - 1))
    ) (lib.range 0 (builtins.length xs - 2));

  stripMask =
    s:
    let
      parts = lib.splitString "/" (toString s);
    in
    if builtins.length parts == 0 then "" else builtins.elemAt parts 0;
in
{
  inherit
    assert_
    isContainerAttr
    containersOf
    pairs
    stripMask
    ;
}
