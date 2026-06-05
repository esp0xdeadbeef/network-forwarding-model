{ lib, self ? { outPath = ./.; }, ... }:

let
  common = import ./common.nix { inherit lib self; };
  inherit (common) clean ipv4ValuesFrom isPublicIPv4 recordSet;

  destAddress =
    destination:
    let
      values = ipv4ValuesFrom destination;
    in
    if values == [ ] then null else builtins.head values;

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

  deniedRecord =
    topo: recordsByAddress: idx: path:
    let
      address = destAddress (path.destination or { });
      class = if address == null then null else recordsByAddress.${address} or null;
    in
    if address == null || class == null || (class.modelOwned or false) != true || !(broadWanOnly topo path) then
      null
    else
      {
        id = "public-ipv4-broad-wan-denial::${toString idx}";
        relationId = path.relationId or null;
        source = path.source or null;
        destination = path.destination or null;
        destinationAddress = address;
        destinationClass = class.destinationClass;
        ownerName = class.ownerName;
        allowed = false;
        reason = "broad-wan-does-not-authorize-model-owned-public-ipv4";
        diagnostic = "model-owned public IPv4 destination requires explicit public-service or public-ingress policy";
      };

  authorizationRecord =
    recordsByAddress: idx: path:
    let
      address = destAddress (path.destination or { });
      class = if address == null then null else recordsByAddress.${address} or null;
    in
    if address == null || class == null || (class.modelOwned or false) != true || !(hasExplicitShortcutPolicy path) then
      null
    else
      {
        id = "public-ipv4-shortcut-authorization::${toString idx}";
        relationId = path.relationId or null;
        destinationAddress = address;
        destinationClass = class.destinationClass;
        ownerName = class.ownerName;
        allowed = true;
        reason = "explicit-public-service-or-ingress-policy";
      };

  genericRecords =
    topo: ownedByAddress:
    recordSet (
      lib.filter (record: record != null) (
        lib.imap0
          (idx: path:
            let
              address = destAddress (path.destination or { });
            in
            if address == null || !(isPublicIPv4 address) || builtins.hasAttr address ownedByAddress then
              null
            else
              {
                id = "public-ipv4-destination::${toString address}";
                family = 4;
                inherit address;
                destinationClass = "generic-wan-internet";
                ownerKind = "external";
                ownerName = null;
                source = "trafficPaths.destination";
                serviceName = null;
                publicIngress = false;
                genericWanInternet = true;
                modelOwned = false;
              })
          (topo.trafficPaths or [ ])
      )
    );

in
{
  build =
    { topo
    , ownedByAddress
    , recordsByAddress
    ,
    }:
    let
      denied = lib.filter (x: x != null) (
        lib.imap0 (idx: path: deniedRecord topo recordsByAddress idx path) (topo.trafficPaths or [ ])
      );
      authorized = lib.filter (x: x != null) (
        lib.imap0 (idx: path: authorizationRecord recordsByAddress idx path) (topo.trafficPaths or [ ])
      );
    in
    {
      inherit denied authorized;
      generic = genericRecords topo ownedByAddress;
      diagnostics = recordSet (
        map
          (record: {
            id = "public-ipv4-diagnostic::${record.id}";
            severity = "error";
            message = record.diagnostic;
            relatedDenial = record.id;
            destinationAddress = record.destinationAddress;
            relationId = record.relationId;
          })
          denied
      );
    };
}
