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

  recordSummary =
    record:
    "${record.address}:${record.destinationClass}:${toString (record.ownerKind or "missing")}:${toString (record.ownerName or "missing")}:${toString (record.source or "missing")}";

  recordsForAddress = records: address:
    lib.filter (record: (record.address or null) == address) records;

  duplicateAddresses =
    records:
    lib.filter
      (address: builtins.length (recordsForAddress records address) > 1)
      (lib.unique (map (record: record.address) records));

  invalidOwnerRecords =
    records:
    lib.filter
      (
        record:
        (record.ownerKind or null) == null
        || (record.ownerName or null) == null
        || (record.ownerName or "") == ""
        || (record.source or null) == null
      )
      records;

  validateOwnedRecords =
    records:
    let
      duplicates = duplicateAddresses records;
      invalidOwners = invalidOwnerRecords records;
      duplicateDetails =
        map
          (address:
            "${address}=[${builtins.concatStringsSep "," (map recordSummary (recordsForAddress records address))}]")
          duplicates;
    in
    if duplicates != [ ] then
      throw "ambiguous-public-ipv4-destination-ownership: ${builtins.concatStringsSep "; " duplicateDetails}"
    else if invalidOwners != [ ] then
      throw "invalid-public-ipv4-destination-owner: ${builtins.concatStringsSep "; " (map recordSummary invalidOwners)}"
    else
      records;

in
{
  build =
    topo:
    let
      ownedRecords = validateOwnedRecords (ownershipRecords.build topo);
      ownedClassRecords = recordSet ownedRecords;
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
      shortcutPolicyDenials = recordSet pathResult.shortcutDenied;
      broadWanDenials = recordSet pathResult.denied;
      diagnostics = pathResult.diagnostics;
    };
}
