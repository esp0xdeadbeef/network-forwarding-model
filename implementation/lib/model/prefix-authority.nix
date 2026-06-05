{ lib, self ? { outPath = ./.; }, ... }:

let
  common = import ./prefix-authority/common.nix { inherit lib self; };
  recordsMod = import ./prefix-authority/records.nix { inherit lib self; };
  requestsMod = import ./prefix-authority/requests.nix { inherit lib self; };
in
{
  build =
    { topo
    , tenantPrefixOwners
    ,
    }:
    let
      explicit = topo.prefixAuthority or { };
      reservations =
        if builtins.isList (explicit.reservations or null) then
          explicit.reservations
        else if builtins.isList (topo.prefixReservations or null) then
          topo.prefixReservations
        else
          [ ];
      requests =
        if builtins.isList (explicit.consumerRequests or null) then
          explicit.consumerRequests
        else if builtins.isList (topo.prefixConsumerRequests or null) then
          topo.prefixConsumerRequests
        else
          [ ];

      records = common.listToAttrsById (recordsMod.build { inherit tenantPrefixOwners reservations; });
      consumerEligibilityRecords = requestsMod.classify records requests;
      deniedSpaceRecords = lib.filter (record: record.allowed == false) consumerEligibilityRecords;
    in
    {
      records = records;
      consumerEligibility = common.listToAttrsById consumerEligibilityRecords;
      deniedSpace = common.listToAttrsById deniedSpaceRecords;
    };
}
