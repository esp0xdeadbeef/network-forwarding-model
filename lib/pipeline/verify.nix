{ lib }:

{ input }:

let

  compileContract = import ../contract/compile.nix { inherit lib; };

  compiled = compileContract { inherit input; };

  sites = lib.concatMapAttrs (
    _org: orgValue:
    if builtins.isAttrs orgValue then lib.filterAttrs (_k: v: builtins.isAttrs v) orgValue else { }
  ) compiled;

  checked = lib.mapAttrs (
    _siteName: site:
    assert (builtins.isAttrs site);
    assert (site ? nodes);
    assert (site ? processCell);
    true
  ) sites;
in
builtins.deepSeq checked true
