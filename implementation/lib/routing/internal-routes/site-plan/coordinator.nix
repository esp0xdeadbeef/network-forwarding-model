{ }:

let
  smsRoot = "FS-940-HDS-010-SDS-020";

  expectedSubmodules = [
    { id = "${smsRoot}-SMS-020"; name = "route-atom-index"; }
    { id = "${smsRoot}-SMS-030"; name = "source-eligibility-matrix"; }
    { id = "${smsRoot}-SMS-040"; name = "next-hop-equivalence-table"; }
    { id = "${smsRoot}-SMS-050"; name = "forwarding-equivalence-group-planner"; }
    { id = "${smsRoot}-SMS-060"; name = "route-exception-layer"; }
    { id = "${smsRoot}-SMS-070"; name = "one-pass-route-materializer"; }
    { id = "${smsRoot}-SMS-080"; name = "route-cardinality-equivalence-diagnostics"; }
  ];

  expectedIds = map (module: module.id) expectedSubmodules;

  listLength = xs: builtins.length xs;

  at = xs: i: builtins.elemAt xs i;

  idAt = records: i: (at records i).id or null;

  hasId = id: records: builtins.any (record: (record.id or null) == id) records;

  missingIds = records: builtins.filter (id: !(hasId id records)) expectedIds;

  orderFailures =
    records:
    let
      max = if listLength records < listLength expectedIds then listLength records else listLength expectedIds;
      go =
        i:
        if i >= max then
          [ ]
        else
          let
            expected = at expectedIds i;
            actual = idAt records i;
          in
          (if actual == expected then [ ] else [ { inherit expected actual; position = i + 1; } ]) ++ go (i + 1);
    in
    go 0;

  authoritativeRouteAtomRecords = records: builtins.filter (record: record.claimsRouteAtomAuthority or false) records;

  require =
    condition: message:
    if condition then true else throw message;

in
{
  inherit expectedSubmodules expectedIds;

  build =
    { submoduleRecords
    , testedHypothesis
    , siteId ? null
    ,
    }:
    let
      _hypothesis = require (
        builtins.isString testedHypothesis && testedHypothesis != ""
      ) "FS-940-HDS-010-SDS-020-SMS-010 coordinator: missing tested hypothesis";

      missing = missingIds submoduleRecords;
      _missing = require (
        missing == [ ]
      ) "FS-940-HDS-010-SDS-020-SMS-010 coordinator: missing required submodule output ${builtins.concatStringsSep "," missing}";

      order = orderFailures submoduleRecords;
      firstOrderFailure = if order == [ ] then null else builtins.head order;
      _order = require (
        order == [ ]
      ) "FS-940-HDS-010-SDS-020-SMS-010 coordinator: out-of-order submodule output at position ${toString firstOrderFailure.position}; expected ${firstOrderFailure.expected}, got ${toString firstOrderFailure.actual}";

      routeAtomAuthorities = authoritativeRouteAtomRecords submoduleRecords;
      _authority = require (
        listLength routeAtomAuthorities == 1
      ) "FS-940-HDS-010-SDS-020-SMS-010 coordinator: conflicting route atom authority surfaces";

      records =
        map
          (
            record:
            record
            // {
              completed = true;
              coordinator = "${smsRoot}-SMS-010";
            }
          )
          submoduleRecords;
    in
    assert _hypothesis;
    assert _missing;
    assert _order;
    assert _authority;
    {
      inherit records;
      diagnostics = {
        coordinator = "${smsRoot}-SMS-010";
        completionRecordCount = listLength records;
        expectedSubmoduleCount = listLength expectedIds;
        routeAtomAuthority = (builtins.head routeAtomAuthorities).id;
        inherit siteId testedHypothesis;
      };
    };
}
