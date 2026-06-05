{ lib, self ? { outPath = ./.; }, ... }:

let
  allConsumers = [
    "advertisement"
    "assignment"
    "exposure"
    "route"
    "translation"
  ];

  denyAll = builtins.listToAttrs (
    map (consumer: {
      name = consumer;
      value = false;
    }) allConsumers
  );

  eligibilityForClass =
    authorityClass:
    if authorityClass == "access-subnet-pool" then
      denyAll // {
        assignment = true;
        route = true;
      }
    else if authorityClass == "routed-client-prefix" || authorityClass == "delegated-client-prefix" then
      denyAll // {
        advertisement = true;
        assignment = true;
        exposure = true;
        route = true;
      }
    else if authorityClass == "host-only-provider-prefix" then
      denyAll // {
        route = true;
      }
    else if authorityClass == "nat66-egress-prefix" then
      denyAll // {
        translation = true;
      }
    else
      denyAll;

  childPurposeOf =
    authorityClass:
    if authorityClass == "access-subnet-pool" then
      "tenant-or-access-assignment"
    else if authorityClass == "routed-client-prefix" then
      "downstream-client-routing"
    else if authorityClass == "delegated-client-prefix" then
      "downstream-client-delegation"
    else if authorityClass == "host-only-provider-prefix" then
      "provider-endpoint-host-address"
    else if authorityClass == "nat66-egress-prefix" then
      "translation-egress-source"
    else
      "reserved-or-unassigned";

  listToAttrsById =
    records:
    builtins.listToAttrs (
      map (record: {
        name = record.id;
        value = record;
      }) records
    );

in
{
  inherit
    allConsumers
    childPurposeOf
    denyAll
    eligibilityForClass
    listToAttrsById
    ;
}
