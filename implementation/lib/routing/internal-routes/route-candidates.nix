{ baseLinkName
, hopNode
, isOverlay
, isP2p ? false
, link
, lib
, nodeName
, preferScopedLane ? false
, preferredAccessNodes ? [ ]
, preferredUplinks
, routeContext
, routeGraph ? null
, topo
,
}:

let
  inherit (routeContext) laneAccessNodeNameFromLink laneUplinkNameFromLink;

  links = topo.links or { };
  candidates =
    if routeGraph != null then
      routeGraph.linksBetween nodeName hopNode
    else
      builtins.sort (a: b: a < b) (
        builtins.filter
          (
            lname:
            let
              l = links.${lname};
              members = link.membersOf l;
            in
            builtins.elem nodeName members && builtins.elem hopNode members
          )
          (builtins.attrNames links)
      );

  preferredCandidates =
    if preferredUplinks == [ ] then
      [ ]
    else
      builtins.filter
        (
          lname:
          let
            uplinkName = laneUplinkNameFromLink links.${lname};
          in
          uplinkName != null && builtins.elem uplinkName preferredUplinks
        )
        candidates;

  preferredAccessSet = lib.unique (map toString (lib.filter (x: x != null) preferredAccessNodes));

  preferredAccessCandidates =
    if preferredAccessSet == [ ] then
      [ ]
    else
      builtins.filter
        (
          lname:
          let
            accessNodeName = laneAccessNodeNameFromLink links.${lname};
          in
          accessNodeName != null && builtins.elem accessNodeName preferredAccessSet
        )
        candidates;

  scopedCandidates =
    if preferredCandidates != [ ] && preferredAccessCandidates != [ ] then
      builtins.filter (lname: builtins.elem lname preferredAccessCandidates) preferredCandidates
    else if preferredCandidates != [ ] then
      preferredCandidates
    else
      preferredAccessCandidates;
in
if preferScopedLane then
  scopedCandidates
else if isOverlay && preferredCandidates != [ ] && preferredAccessCandidates != [ ] then
  builtins.filter (lname: builtins.elem lname preferredAccessCandidates) preferredCandidates
else if (isOverlay || isP2p) && preferredCandidates != [ ] then
  preferredCandidates
else if isOverlay && preferredAccessCandidates != [ ] then
  preferredAccessCandidates
else if isP2p && candidates != [ ] then
  candidates
else if baseLinkName == null then
  [ ]
else
  [ baseLinkName ]
