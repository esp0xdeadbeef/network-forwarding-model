{ lib, self ? { outPath = ./.; }, ... }:
# FS-500-HDS-010-SDS-010-SMS-010: Traffic path validation against
# communication contract.  Validates:
# - SN1: relationId must exist in allowedRelations or relations
# - SN2: path action must match relation action
#
# Returns: { diagnostics = { ... }; validPaths = [ ... ]; }

let
  clean = v: if v == null then null else builtins.replaceStrings [ " " ] [ "" ] (toString v);

  # uniqueBy is not available in all nixpkgs versions; define it locally.
  # Deduplicates a list by a key function, preserving first-occurrence order.
  uniqueBy = f: list:
    builtins.foldl' (acc: x:
      let key = f x; in
      if builtins.elem key (map f acc) then acc else acc ++ [ x ]
    ) [ ] list;

  matchesRelation =
    path: relation:
    let
      pathSrc = path.source or { };
      relFrom = relation.from or { };
      pathDest = path.destination or { };
      relTo = relation.to or { };
    in
    # Match by ID first (strongest signal)
    (clean (path.relationId or null)) == (clean (relation.id or null))
    # Fallback: match by source/destination kind+name
    || (
      (clean (pathSrc.kind or null)) == (clean (relFrom.kind or null))
      && (clean (pathSrc.name or null)) == (clean (relFrom.name or null))
      && (clean (pathDest.kind or null)) == (clean (relTo.kind or null))
      && (clean (pathDest.name or null)) == (clean (relTo.name or null))
    );

  findMatchingRelation =
    path: relations:
    let
      matches = lib.filter (r: matchesRelation path r) relations;
    in
    if matches == [ ] then null else builtins.head matches;

  diagnosticFor =
    idx: path: relations:
    let
      matchedRel = findMatchingRelation path relations;
    in
    # SN1: No matching relation found (no evidence trace)
    if matchedRel == null then
      {
        id = "traffic-path-evidence-diagnostic::${toString idx}";
        severity = "error";
        message =
          "traffic path \"${toString (path.relationId or "<no-relationId>")}\""
          + " has no matching evidence in communication contract";
        relatedPath = path.relationId or null;
        missingEvidence = true;
        contractContradiction = false;
      }
    # SN2: Path action contradicts relation action
    else if (path.action or "allow") != (matchedRel.action or "allow") then
      {
        id = "traffic-path-contradiction-diagnostic::${toString idx}";
        severity = "error";
        message =
          "traffic path \"${toString (path.relationId or "<no-relationId>")}\""
          + " action=${toString (path.action or "allow")}"
          + " contradicts relation action=${toString (matchedRel.action or "allow")}";
        relatedPath = path.relationId or null;
        missingEvidence = false;
        contractContradiction = true;
        pathAction = path.action or "allow";
        relationAction = matchedRel.action or "allow";
      }
    else
      null;

  isValidPath =
    path: relations:
    let
      matchedRel = findMatchingRelation path relations;
    in
    matchedRel != null && (path.action or "allow") == (matchedRel.action or "allow");

in
{
  validate =
    topo:
    let
      paths = topo.trafficPaths or [ ];
      allRelations =
        (topo.communicationContract or { }).allowedRelations or [ ]
        ++ (topo.communicationContract or { }).relations or [ ];
      uniqueRelations = uniqueBy (r: clean r.id or null) allRelations;

      diagnosticsList = lib.filter
        (x: x != null)
        (lib.imap0 (idx: path: diagnosticFor idx path uniqueRelations) paths);

      validPaths = lib.filter (path: isValidPath path uniqueRelations) paths;
      invalidPaths = lib.filter (path: !(isValidPath path uniqueRelations)) paths;

      diagnosticsByPath = builtins.listToAttrs (
        lib.imap0
          (idx: diag: {
            name = diag.id or "diagnostic-${toString idx}";
            value = diag;
          })
          diagnosticsList
      );

    in
    {
      validPathCount = builtins.length validPaths;
      invalidPathCount = builtins.length invalidPaths;
      diagnostics = diagnosticsByPath;
      validPaths = validPaths;
      invalidPaths = invalidPaths;
    };
}
