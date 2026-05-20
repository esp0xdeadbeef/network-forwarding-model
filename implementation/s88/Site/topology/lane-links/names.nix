{ lib, ... }:

let
  sortedUnitNames = unitNames: lib.sort (a: b: a < b) unitNames;

  endpointPair =
    endpointA: endpointB:
    let
      endpointAName = toString endpointA;
      endpointBName = toString endpointB;
    in
    if endpointAName < endpointBName then
      {
        first = endpointAName;
        second = endpointBName;
      }
    else
      {
        first = endpointBName;
        second = endpointAName;
      };
in
{
  firstUnitByRole =
    { unitNames
    , rolesResult
    , role
    ,
    }:
    let
      hits = lib.filter (n: rolesResult.roleFromInput (toString n) == role) (sortedUnitNames unitNames);
    in
    if hits == [ ] then null else toString (builtins.head hits);

  unitsByRole =
    { unitNames
    , rolesResult
    , role
    ,
    }:
    map toString (lib.filter (n: rolesResult.roleFromInput (toString n) == role) (sortedUnitNames unitNames));

  canonicalP2pLinkNameForEndpoints =
    endpointA: endpointB:
    let
      pair = endpointPair endpointA endpointB;
    in
    "p2p-${pair.first}-${pair.second}";

  canonicalP2pLinkNameForEndpointsWithSuffix =
    endpointA: endpointB: suffix:
    let
      pair = endpointPair endpointA endpointB;
    in
    "p2p-${pair.first}-${pair.second}--${toString suffix}";
}
