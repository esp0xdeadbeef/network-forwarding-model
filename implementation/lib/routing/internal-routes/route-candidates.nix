{
  baseLinkName,
  graph,
  hopNode,
  isOverlay,
  laneUplinkNameFromLinkName,
  nodeName,
  preferredUplinks,
  topo,
}:

let
  links = topo.links or { };
  candidates = builtins.sort (a: b: a < b) (
    builtins.filter (
      lname:
      let
        l = links.${lname};
        members = graph.membersOf l;
      in
      builtins.elem nodeName members && builtins.elem hopNode members
    ) (builtins.attrNames links)
  );

  preferredCandidates =
    if preferredUplinks == [ ] then
      [ ]
    else
      builtins.filter (
        lname:
        let
          uplinkName = laneUplinkNameFromLinkName lname;
        in
        uplinkName != null && builtins.elem uplinkName preferredUplinks
      ) candidates;
in
if isOverlay && preferredCandidates != [ ] then
  preferredCandidates
else if baseLinkName == null then
  [ ]
else
  [ baseLinkName ]
