{ lib, self ? { outPath = ./.; }, ... }:

let
  link = import (self.outPath + "/implementation/lib/topology/link-utils.nix") { inherit lib self; };
  routeFields = import (self.outPath + "/implementation/lib/routing/loopbacks/route-fields.nix") { inherit lib self; };

  laneMeta = link:
    if builtins.isAttrs (link.laneMeta or null) then link.laneMeta else { };

in
{
  withPreferences =
    {
      links,
      from,
      to,
      preferredUplinks ? [ ],
      preferredAccessNodes ? [ ],
      routeGraph ? null,
    }:
    let
      candidates =
        if routeGraph != null then
          routeGraph.linksBetween from to
        else
          lib.sort (a: b: a < b) (
            lib.filter (
              lname:
              let
                l = links.${lname};
                members = link.membersOf l;
              in
              lib.elem from members && lib.elem to members
            ) (builtins.attrNames links)
          );

      preferredUplinkSet = lib.unique (map toString (lib.filter (x: x != null) preferredUplinks));
      preferredAccessSet = lib.unique (map toString (lib.filter (x: x != null) preferredAccessNodes));

      preferredUplinkCandidates = lib.filter (
        lname:
        let
          uplinkName = (laneMeta links.${lname}).uplink or null;
        in
        preferredUplinkSet != [ ] && uplinkName != null && builtins.elem uplinkName preferredUplinkSet
      ) candidates;

      preferredAccessCandidates = lib.filter (
        lname:
        let
          accessNodeName = (laneMeta links.${lname}).access or null;
        in
        preferredAccessSet != [ ] && accessNodeName != null && builtins.elem accessNodeName preferredAccessSet
      ) candidates;

      chosen =
        if preferredUplinkCandidates != [ ] && preferredAccessCandidates != [ ] then
          let overlap = lib.filter (lname: builtins.elem lname preferredAccessCandidates) preferredUplinkCandidates;
          in if overlap != [ ] then builtins.head overlap else builtins.head preferredUplinkCandidates
        else if preferredUplinkCandidates != [ ] then
          builtins.head preferredUplinkCandidates
        else if preferredAccessCandidates != [ ] then
          builtins.head preferredAccessCandidates
        else if candidates != [ ] then
          builtins.head candidates
        else
          null;

      linkObj = if chosen == null then null else links.${chosen};
      epTo = if linkObj == null then { } else link.getEp chosen linkObj to;
    in
    {
      linkName = chosen;
      via4 = if epTo ? addr4 && epTo.addr4 != null then routeFields.strip epTo.addr4 else null;
      via6 = if epTo ? addr6 && epTo.addr6 != null then routeFields.strip epTo.addr6 else null;
    };
}
