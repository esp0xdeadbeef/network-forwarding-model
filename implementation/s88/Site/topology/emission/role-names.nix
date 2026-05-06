{ lib, self ? { outPath = ./.; }, ... }:

let
  common = import (self.outPath + "/implementation/s88/Site/topology/common.nix") { inherit lib self; };

in
{
  finalPolicyNodeName =
    {
      normalizedRouteSite,
      policyNodeName,
    }:
    if normalizedRouteSite ? policyNodeName && normalizedRouteSite.policyNodeName != null then
      normalizedRouteSite.policyNodeName
    else if policyNodeName != null then
      policyNodeName
    else
      common.firstNodeNameByRole (normalizedRouteSite.nodes or { }) "policy";

  upstreamSelectorNodeName =
    {
      normalizedRouteSite,
      upstreamSelectorNodeName,
    }:
    let
      nodes = normalizedRouteSite.nodes or { };
      candidate =
        if normalizedRouteSite ? upstreamSelectorNodeName && normalizedRouteSite.upstreamSelectorNodeName != null then
          normalizedRouteSite.upstreamSelectorNodeName
        else if upstreamSelectorNodeName != null then
          upstreamSelectorNodeName
        else
          common.firstNodeNameByRole nodes "upstream-selector";
    in
    if candidate != null && nodes ? "${candidate}" && (nodes.${candidate}.role or null) == "upstream-selector" then
      candidate
    else
      null;

  validateUpstreamSelector =
    {
      enterprise,
      siteId,
      normalizedRouteSite,
      emittedUpstreamSelectorNodeName,
    }:
    if emittedUpstreamSelectorNodeName == null then
      true
    else if
      (normalizedRouteSite.nodes or { } ? "${emittedUpstreamSelectorNodeName}")
      && ((normalizedRouteSite.nodes.${emittedUpstreamSelectorNodeName}.role or null) == "upstream-selector")
    then
      true
    else
      throw ''
        network-forwarding-model: invalid emitted upstreamSelectorNodeName

        site: ${enterprise}.${siteId}
        candidate: ${toString emittedUpstreamSelectorNodeName}
        nodes: ${builtins.toJSON (builtins.attrNames (normalizedRouteSite.nodes or { }))}
      '';
}
