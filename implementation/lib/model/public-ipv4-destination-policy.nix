{ lib, self ? { outPath = ./.; }, ... }:

let
  common = import ./public-ipv4-destination-policy/common.nix { inherit lib self; };
  ownershipRecords = import ./public-ipv4-destination-policy/ownership-records.nix { inherit lib self; };
  pathPolicy = import ./public-ipv4-destination-policy/path-policy.nix { inherit lib self; };
  inherit (common) recordSet;

  byAddress =
    records:
    builtins.listToAttrs (
      map
        (record: {
          name = record.address;
          value = record;
        })
        (builtins.attrValues records)
    );

in
{
  build =
    topo:
    let
      ownedClassRecords = recordSet (ownershipRecords.build topo);
      ownedByAddress = byAddress ownedClassRecords;
      genericClassRecords = (pathPolicy.build {
        inherit topo ownedByAddress;
        recordsByAddress = ownedByAddress;
      }).generic;
      classRecords = genericClassRecords // ownedClassRecords;
      recordsByAddress = byAddress classRecords;
      pathResult = pathPolicy.build {
        inherit topo ownedByAddress recordsByAddress;
      };
    in
    {
      destinationClasses = classRecords;
      shortcutAuthorizations = recordSet pathResult.authorized;
      broadWanDenials = recordSet pathResult.denied;
      diagnostics = pathResult.diagnostics;
    };
}
