{ lib }:

let
  common = import ./common.nix { inherit lib; };

  isPair =
    x:
    builtins.isList x
    && builtins.length x == 2
    && builtins.isString (builtins.elemAt x 0)
    && builtins.isString (builtins.elemAt x 1);

  uniq = xs: lib.unique xs;

in
{
  check =
    { site }:
    let
      siteName = toString (site.siteName or "<unknown-site>");
      siteKey = toString (site.compilerIR.id or site.siteName or "<unknown-siteKey>");
      ir = site.compilerIR or { };

      ordering = ir.transit.ordering or null;

      _present = common.assert_ (ordering != null && builtins.isList ordering) ''
        invariants(transit-ordering-valid):

        missing required compilerIR.transit.ordering

          siteKey: ${siteKey}
          site:    ${siteName}
      '';

      _pairsOk = common.assert_ (lib.all isPair ordering) ''
        invariants(transit-ordering-valid):

        transit.ordering must be a list of 2-element string pairs

          siteKey: ${siteKey}
          site:    ${siteName}
      '';

      pairs = lib.filter isPair ordering;

      edges = map (p: {
        a = builtins.elemAt p 0;
        b = builtins.elemAt p 1;
      }) pairs;

      _noSelf = common.assert_ (lib.all (e: e.a != e.b) edges) ''
        invariants(transit-ordering-valid):

        transit.ordering contains a self-edge

          siteKey: ${siteKey}
          site:    ${siteName}
      '';

      unitsInOrdering = uniq (
        lib.concatMap (e: [
          e.a
          e.b
        ]) edges
      );

      knownUnits =
        let
          fromNodes = builtins.attrNames (site.nodes or { });
          fromIR =
            let
              lbs = ir.routerLoopbacks or { };
            in
            builtins.attrNames lbs;
        in
        uniq (fromNodes ++ fromIR);

      unknownUnits = lib.filter (u: !(lib.elem u knownUnits)) unitsInOrdering;

      _known = common.assert_ (unknownUnits == [ ]) ''
        invariants(transit-ordering-valid):

        transit.ordering references unknown unit(s)

          siteKey: ${siteKey}
          site:    ${siteName}

          unknown: ${lib.concatStringsSep ", " unknownUnits}
      '';
    in
    builtins.seq _present (builtins.seq _pairsOk (builtins.seq _noSelf (builtins.seq _known true)));
}
