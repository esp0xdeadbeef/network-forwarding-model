{ lib, self ? { outPath = ./.; }, ... }:

let
  common = import ./common.nix { inherit lib self; };
  helpers = import ./path-policy-helpers.nix { inherit lib self; };
  inherit (common) isPublicIPv4 recordSet;
  inherit (helpers)
    broadWanOnly
    destinationAddress
    hasExplicitShortcutPolicy
    hasReturnBehavior
    modeledClass
    pathReturnBehavior
    ;

  deniedRecord =
    topo: recordsByAddress: idx: path:
    let
      address = destinationAddress recordsByAddress (path.destination or { });
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
    topo: recordsByAddress: idx: path:
    let
      modeled = modeledClass recordsByAddress path;
      address = modeled.address;
      class = modeled.class;
      returnBehavior = pathReturnBehavior topo path;
    in
    if
      address == null
      || class == null
      || (class.modelOwned or false) != true
      || !(hasExplicitShortcutPolicy path)
      || returnBehavior == null
    then
      null
    else
      {
        id = "public-ipv4-shortcut-authorization::${toString idx}";
        relationId = path.relationId or null;
        destinationAddress = address;
        destinationClass = class.destinationClass;
        ownerName = class.ownerName;
        inherit returnBehavior;
        allowed = true;
        reason = "explicit-public-service-or-ingress-policy";
      };

  shortcutDenialRecord =
    topo: recordsByAddress: idx: path:
    let
      modeled = modeledClass recordsByAddress path;
      address = modeled.address;
      class = modeled.class;
    in
    if
      address == null
      || class == null
      || (class.modelOwned or false) != true
      || !(hasExplicitShortcutPolicy path)
      || hasReturnBehavior topo path
    then
      null
    else
      {
        id = "public-ipv4-shortcut-denial::${toString idx}";
        relationId = path.relationId or null;
        source = path.source or null;
        destination = path.destination or null;
        destinationAddress = address;
        destinationClass = class.destinationClass;
        ownerName = class.ownerName;
        allowed = false;
        reason = "missing-return-behavior";
        diagnostic = "model-owned public IPv4 shortcut requires explicit return behavior";
      };

  genericRecords =
    topo: ownedByAddress:
    recordSet (
      lib.filter (record: record != null) (
        lib.imap0
          (idx: path:
            let
              address = destinationAddress ownedByAddress (path.destination or { });
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
        lib.imap0 (idx: path: authorizationRecord topo recordsByAddress idx path) (topo.trafficPaths or [ ])
      );
      shortcutDenied = lib.filter (x: x != null) (
        lib.imap0 (idx: path: shortcutDenialRecord topo recordsByAddress idx path) (topo.trafficPaths or [ ])
      );
      diagnosticRecords = denied ++ shortcutDenied;
    in
    {
      inherit denied authorized shortcutDenied;
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
          diagnosticRecords
      );
    };
}
