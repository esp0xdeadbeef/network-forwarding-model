{
  lib,
  self ? {
    outPath = ./.;
  },
  ...
}:

let
  link = import (self.outPath + "/implementation/lib/topology/link-utils.nix") { inherit lib self; };
  routeFields = import (self.outPath + "/implementation/lib/routing/loopbacks/route-fields.nix") {
    inherit lib self;
  };

  laneMeta = link: if builtins.isAttrs (link.laneMeta or null) then link.laneMeta else { };

  hopForLink =
    links: to: lname:
    let
      linkObj = links.${lname};
      epTo = if linkObj == null then { } else link.getEp lname linkObj to;
    in
    {
      linkName = lname;
      via4 = if epTo ? addr4 && epTo.addr4 != null then routeFields.strip epTo.addr4 else null;
      via6 = if epTo ? addr6 && epTo.addr6 != null then routeFields.strip epTo.addr6 else null;
    };

  candidateLinks =
    {
      links,
      from,
      to,
      routeGraph ? null,
    }:
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

  preferredLinks =
    {
      links,
      candidates,
      preferredUplinks ? [ ],
      preferredAccessNodes ? [ ],
    }:
    let
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
        preferredAccessSet != [ ]
        && accessNodeName != null
        && builtins.elem accessNodeName preferredAccessSet
      ) candidates;
    in
    {
      inherit
        preferredUplinkSet
        preferredAccessSet
        preferredUplinkCandidates
        preferredAccessCandidates
        ;
    };
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
      candidates = candidateLinks {
        inherit
          links
          from
          to
          routeGraph
          ;
      };
      preferred = preferredLinks {
        inherit
          links
          candidates
          preferredUplinks
          preferredAccessNodes
          ;
      };

      chosen =
        if preferred.preferredUplinkCandidates != [ ] && preferred.preferredAccessCandidates != [ ] then
          let
            overlap = lib.filter (
              lname: builtins.elem lname preferred.preferredAccessCandidates
            ) preferred.preferredUplinkCandidates;
          in
          if overlap != [ ] then builtins.head overlap else builtins.head preferred.preferredUplinkCandidates
        else if preferred.preferredUplinkCandidates != [ ] then
          builtins.head preferred.preferredUplinkCandidates
        else if preferred.preferredAccessCandidates != [ ] then
          builtins.head preferred.preferredAccessCandidates
        else if candidates != [ ] then
          builtins.head candidates
        else
          null;
    in
    if chosen == null then
      {
        linkName = null;
        via4 = null;
        via6 = null;
      }
    else
      hopForLink links to chosen;

  # Every parallel link between the same two nodes gets the loopback route.
  # A hub-and-spoke policy/selector pair has one link per lane, and a
  # loopback (for example the ingress-SNAT source on the core) must be
  # reachable through whichever lane carries the return traffic — not only
  # through the lexicographically first link.
  allHops =
    {
      links,
      from,
      to,
      preferredUplinks ? [ ],
      preferredAccessNodes ? [ ],
      routeGraph ? null,
    }:
    let
      candidates = candidateLinks {
        inherit
          links
          from
          to
          routeGraph
          ;
      };
      preferred = preferredLinks {
        inherit
          links
          candidates
          preferredUplinks
          preferredAccessNodes
          ;
      };

      chosenLinks =
        if preferred.preferredUplinkCandidates != [ ] && preferred.preferredAccessCandidates != [ ] then
          let
            overlap = lib.filter (
              lname: builtins.elem lname preferred.preferredAccessCandidates
            ) preferred.preferredUplinkCandidates;
          in
          if overlap != [ ] then overlap else preferred.preferredUplinkCandidates
        else if preferred.preferredUplinkCandidates != [ ] then
          preferred.preferredUplinkCandidates
        else if preferred.preferredAccessCandidates != [ ] then
          preferred.preferredAccessCandidates
        else
          candidates;
    in
    map (hopForLink links to) chosenLinks;
}
