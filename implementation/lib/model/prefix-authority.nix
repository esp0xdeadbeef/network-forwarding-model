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
      routeExportPreconditionRequests =
        if builtins.isList (explicit.routeExportPreconditions or null) then
          explicit.routeExportPreconditions
        else if builtins.isList (explicit.returnRoutePreconditions or null) then
          explicit.returnRoutePreconditions
        else
          lib.filter (request: builtins.isAttrs request) requests;
      guaPlacementPreconditionRequests =
        if builtins.isList (explicit.guaPlacementPreconditions or null) then
          explicit.guaPlacementPreconditions
        else if builtins.isList (explicit.guaPlacementRequests or null) then
          explicit.guaPlacementRequests
        else
          [ ];

      records = common.listToAttrsById (recordsMod.build { inherit tenantPrefixOwners reservations; });
      consumerEligibilityRecords = requestsMod.classify records requests;
      deniedSpaceRecords = lib.filter (record: record.allowed == false) consumerEligibilityRecords;
      routeExportPreconditionRecords = requestsMod.classifyReturnRoutePreconditions records routeExportPreconditionRequests;
      deniedRouteExportPreconditionRecords = lib.filter (record: record.allowed == false) routeExportPreconditionRecords;
      guaPlacementPreconditionRecords = requestsMod.classifyGuaPlacementPreconditions records guaPlacementPreconditionRequests;
      deniedGuaPlacementPreconditionRecords = lib.filter (record: record.allowed == false) guaPlacementPreconditionRecords;
    in
    {
      records = records;
      consumerEligibility = common.listToAttrsById consumerEligibilityRecords;
      deniedSpace = common.listToAttrsById deniedSpaceRecords;
      routeExportPreconditions = common.listToAttrsById routeExportPreconditionRecords;
      deniedRouteExportPreconditions = common.listToAttrsById deniedRouteExportPreconditionRecords;
      guaPlacementPreconditions = common.listToAttrsById guaPlacementPreconditionRecords;
      deniedGuaPlacementPreconditions = common.listToAttrsById deniedGuaPlacementPreconditionRecords;
    };
}
