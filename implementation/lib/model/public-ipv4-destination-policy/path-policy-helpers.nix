{ lib, self ? { outPath = ./.; }, ... }:

let
  common = import ./common.nix { inherit lib self; };
  inherit (common) clean ipv4ValuesFrom;

  destAddress =
    destination:
    let
      values = ipv4ValuesFrom destination;
    in
    if values == [ ] then null else builtins.head values;

  serviceDestinationAddress =
    recordsByAddress: destination:
    let
      serviceName = clean (destination.name or destination.serviceName or null);
      matches =
        lib.filter
          (
            record:
            (record.ownerKind or null) == "service"
            && (
              clean (record.ownerName or null) == serviceName
              || clean (record.serviceName or null) == serviceName
            )
          )
          (builtins.attrValues recordsByAddress);
    in
    if serviceName == null || matches == [ ] then null else (builtins.head matches).address;

  destinationUplinks =
    destination:
    if (destination.kind or null) != "external" then
      [ ]
    else if builtins.isList (destination.uplinks or null) then
      map toString destination.uplinks
    else if (destination.name or null) != null then
      [ (toString destination.name) ]
    else
      [ ];

  isBroadWanRelation =
    relation:
    (relation.action or "allow") == "allow"
    && (relation.trafficType or "any") == "any"
    && destinationUplinks (relation.to or { }) != [ ];

  sourceMatches =
    left: right:
    (left.kind or null) == (right.kind or null)
    && clean (left.name or null) == clean (right.name or null);

  relationHasExplicitShortcutPolicy =
    relation:
    let
      to = relation.to or { };
    in
    (to.kind or null) == "service"
    || (to.kind or null) == "public-ingress"
    || (relation.publicServicePolicy or false) == true
    || (relation.publicIngressPolicy or false) == true
    || (relation.shortcutPolicy or null) == "explicit";

  relationById =
    topo: relationId:
    let
      matches = lib.filter
        (relation: (relation.id or null) == relationId)
        ((topo.communicationContract or { }).allowedRelations or [ ]);
    in
    if matches == [ ] then null else builtins.head matches;

in
rec {
  destinationAddress =
    recordsByAddress: destination:
    let
      direct = destAddress destination;
      kind = destination.kind or null;
    in
    if direct != null then
      direct
    else if kind == "service" || kind == "public-ingress" then
      serviceDestinationAddress recordsByAddress destination
    else
      null;

  hasExplicitShortcutPolicy =
    path:
    let
      destination = path.destination or { };
    in
    (destination.kind or null) == "service"
    || (destination.kind or null) == "public-ingress"
    || (path.publicServicePolicy or false) == true
    || (path.publicIngressPolicy or false) == true
    || (path.shortcutPolicy or null) == "explicit";

  broadWanOnly =
    topo: path:
    let
      source = path.source or { };
      relations = (topo.communicationContract or { }).allowedRelations or [ ];
      broadMatches = lib.filter
        (relation: isBroadWanRelation relation && sourceMatches source (relation.from or { }))
        relations;
      explicitMatches = lib.filter
        (relation: sourceMatches source (relation.from or { }) && relationHasExplicitShortcutPolicy relation)
        relations;
    in
    broadMatches != [ ] && explicitMatches == [ ] && !(hasExplicitShortcutPolicy path);

  pathReturnBehavior =
    topo: path:
    let
      relation = relationById topo (path.relationId or null);
    in
    path.returnBehavior or (if relation == null then null else relation.returnBehavior or null);

  hasReturnBehavior =
    topo: path:
    (pathReturnBehavior topo path) != null;

  modeledClass =
    recordsByAddress: path:
    let
      address = destinationAddress recordsByAddress (path.destination or { });
      class = if address == null then null else recordsByAddress.${address} or null;
    in
    {
      inherit address class;
    };
}
