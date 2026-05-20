{ lib, self ? { outPath = ./.; }, ... }:

let
  coreUplinksPresent = import (self.outPath + "/implementation/lib/fabric/invariants/core-uplinks-present.nix") { inherit lib self; };
  routes = import (self.outPath + "/implementation/lib/model/routes.nix") { inherit lib self; };

  normalizeRouteList = routes.normalizeRouteDestinationList;

  validateEndpoint =
    unitName: uplink:
    let
      name = uplink.name or "<unknown>";
      addr4 = uplink.addr4 or null;
      peerAddr4 = uplink.peerAddr4 or null;
      addr6 = uplink.addr6 or null;
      peerAddr6 = uplink.peerAddr6 or null;
      routes4 = normalizeRouteList (uplink.ipv4 or [ ]);
      routes6 = normalizeRouteList (uplink.ipv6 or [ ]);

      need4 = addr4 != null || peerAddr4 != null || routes4 != [ ];
      need6 = addr6 != null || peerAddr6 != null || routes6 != [ ];
    in
    if need4 && (addr4 == null || peerAddr4 == null) then
      throw ''
        network-forwarding-model: incomplete IPv4 WAN uplink endpoint

        unit: ${toString unitName}
        uplink: ${toString name}
        expected both addr4 and peerAddr4 when IPv4 uplink reachability is declared
      ''
    else if need6 && (addr6 == null || peerAddr6 == null) then
      throw ''
        network-forwarding-model: incomplete IPv6 WAN uplink endpoint

        unit: ${toString unitName}
        uplink: ${toString name}
        expected both addr6 and peerAddr6 when IPv6 uplink reachability is declared
      ''
    else
      true;

in
{
  requireCoreUnits =
    unitNames:
    if unitNames == [ ] then
      throw "network-forwarding-model: expected at least one unit with role='core'"
    else
      true;

  requireDeclaredUplinks =
    unitNames:
    coreUplinksPresent.assertAny {
      discoveredCoreNames = unitNames;
      expectedInputs = [
        ''site.upstreams.cores.<core> = [ "<uplink>" ... ]''
        ''site.uplinks.cores.<core> = [ { name = "<uplink>"; ... } ... ]''
        "site.nodes.<core>.uplinks = { <uplink> = { ... }; ...; }"
      ];
    };

  requireUniqueForwardingNames =
    nameEntries:
    let
      duplicateNames =
        lib.filter
          (
            uplinkName:
            builtins.length (lib.filter (entry: entry.name == uplinkName) nameEntries) > 1
          )
          (lib.unique (map (entry: entry.name) nameEntries));
    in
    if duplicateNames == [ ] then
      true
    else
      throw ''
        network-forwarding-model: forwarding uplink names must be unique across cores

        duplicate uplink names: ${lib.concatStringsSep ", " duplicateNames}
      '';

  requireCompleteEndpoints =
    specs:
    builtins.foldl'
      (
        acc: spec:
        builtins.seq acc (validateEndpoint spec.unitName spec.uplink)
      )
      true
      specs;
}
