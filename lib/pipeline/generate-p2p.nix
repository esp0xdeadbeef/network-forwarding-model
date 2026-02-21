{ lib }:

{ input }:

let
  compileContract = import ../contract/compile.nix { inherit lib; };
  compiled = compileContract { inherit input; };

  alloc = import ../p2p/alloc.nix { inherit lib; };

  isSite = v: builtins.isAttrs v && v ? nodes;

  sites = lib.concatMapAttrs (
    _org: orgValue:
    if builtins.isAttrs orgValue then lib.filterAttrs (_k: v: isSite v) orgValue else { }
  ) compiled;

  p2pForSite =
    _siteName: site:
    let
      pool = site.p2p-pool or null;

      p2pLinks = if pool == null then { } else alloc.alloc { site = site; };
    in
    {
      inherit pool;

      links = p2pLinks;
    };

in
lib.mapAttrs p2pForSite sites
