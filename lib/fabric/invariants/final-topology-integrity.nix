{ lib, self ? { outPath = ./.; }, ... }:

let
  linkIntegrity = import ./final-topology-links.nix { inherit lib self; };
  transitIntegrity = import ./final-topology-transit.nix { inherit lib self; };
in
{
  check =
    { site }:
    let
      siteName = toString (site.siteName or "<unknown-site>");
      nodes = site.nodes or { };
      links = site.links or { };
      transit = site.transit or { };
      adjacencies = if builtins.isList (transit.adjacencies or null) then transit.adjacencies else [ ];

      linkCheck = linkIntegrity.checkLinks {
        inherit links nodes siteName;
      };

      transitCheck = transitIntegrity.checkTransit {
        inherit adjacencies links siteName;
        inherit (linkCheck) linkIdToName;
      };
    in
    builtins.seq linkCheck.ok transitCheck;
}
