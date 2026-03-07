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

  containersOf = node: builtins.attrNames (lib.filterAttrs isContainerAttr node);

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
