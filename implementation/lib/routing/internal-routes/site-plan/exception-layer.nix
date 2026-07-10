{ }:

let
  sms = "FS-940-HDS-010-SDS-020-SMS-060";

  validateExceptionRow =
    row:
    let
      key = row.equivalenceKey or { };
      diag = row.diagnostics or { };
      excClass = key.exceptionClass or "none";
      isException = excClass != null && excClass != "none";
      hasSummarization = (diag.prefixSummaryCandidateCount or 0) > 0;
      hasAggregation = (diag.rejectedAggregationCount or 0) > 0
        && (diag.prefixSummaryCandidateCount or 0) == 0;
      routeAtomCt = diag.routeAtomCount or 0;
      finalMat = diag.finalMaterializedRouteCount or 0;
      exactDedupe = diag.exactDeduplicationCount or 0;
      isSourceFile = excClass == "runtime-source-file";
      hasCommonGroupMutation =
        isException
        && hasSummarization;
      hasExactnessLoss =
        isSourceFile
        && (finalMat < routeAtomCt
            || (exactDedupe > 0 && finalMat != routeAtomCt));
    in
    if hasCommonGroupMutation then
      builtins.throw "diagnostic.route-exception-mutated-common-group"
    else if hasExactnessLoss then
      builtins.throw "diagnostic.route-exception-exactness-lost"
    else if isException && !hasSummarization then
      row // { exceptionLayer = { validated = true; exceptionClass = excClass; }; }
    else
      row // { exceptionLayer = { validated = true; exceptionClass = excClass; }; };

  countExceptionRows =
    pred: rows:
    builtins.length (
      builtins.filter (
        row:
        let
          key = row.equivalenceKey or { };
          exc = key.exceptionClass or "none";
        in
        pred exc
      ) rows
    );
in
{
  inherit sms;

  build =
    { routeRows }:
    let
      validatedRows = map validateExceptionRow routeRows;

      p2pExactCount = countExceptionRows (exc: exc == "point-to-point-exact") validatedRows;
      runtimeSourceFileCount = countExceptionRows (exc: exc == "runtime-source-file") validatedRows;
      overlayExactCount = countExceptionRows (exc: exc == "overlay-scope-exact") validatedRows;
      uplinkExactCount = countExceptionRows (exc: exc == "selected-uplink-exact") validatedRows;
      totalExceptions = p2pExactCount + runtimeSourceFileCount + overlayExactCount + uplinkExactCount;

      diagnostics = {
        inherit sms;
        source = "after-forwarding-equivalence-groups";
        mutatesCommonGroups = false;
        totalRows = builtins.length validatedRows;
        inherit p2pExactCount runtimeSourceFileCount overlayExactCount uplinkExactCount totalExceptions;
        validated = true;
      };
    in
    {
      inherit validatedRows diagnostics;
    };
}
