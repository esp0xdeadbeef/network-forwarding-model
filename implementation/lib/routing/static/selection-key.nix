{ lib }:

let
  # Fields that belong to the route selection key per SMS FS-315-HDS-010-SDS-010-SMS-010.
  # The key identifies a route selection independent of how it is reached.
  selectionKeyAttrs = [
    "dst"
    "proto"
    "intent"
    "metric"
    "policyOnly"
  ];

  # Fields that constitute the semantic next-hop set.
  # These are the "how" of reaching the destination, not the "which route" identity.
  nextHopAttrs = [
    "via4"
    "via6"
    "via"
    "gateway"
    "gateway4"
    "gateway6"
    "dev"
    "linkName"
    "onlink"
    "lane"
    "scope"
    "overlay"
    "peerSite"
    "reason"
    "src"
  ];

  # Build the route selection key as a stable JSON string of only the key fields.
  selectionKey =
    r:
    let
      keySet = builtins.intersectAttrs
        (builtins.listToAttrs (map (f: { name = f; value = true; }) selectionKeyAttrs))
        r;
    in
    builtins.toJSON keySet;

  # Extract the semantic next-hop set as a sorted, stable JSON representation.
  # Returns a string that is identical for identical next-hop facts.
  nextHopSet =
    r:
    let
      has = name: r ? "${name}" && r.${name} != null;
      str = name: "${name}:${toString r.${name}}";
      parts = builtins.concatLists [
        (if has "via4" then [ (str "via4") ] else [ ])
        (if has "via6" then [ (str "via6") ] else [ ])
        (if has "via" then [ (str "via") ] else [ ])
        (if has "gateway" then [ (str "gateway") ] else [ ])
        (if has "gateway4" then [ (str "gateway4") ] else [ ])
        (if has "gateway6" then [ (str "gateway6") ] else [ ])
        (if has "dev" then [ (str "dev") ] else [ ])
        (if has "linkName" then [ (str "linkName") ] else [ ])
        (if has "onlink" && r.onlink == true then [ "onlink" ] else [ ])
        (if has "lane" then [ "lane:${builtins.toJSON r.lane}" ] else [ ])
        (if has "scope" then [ (str "scope") ] else [ ])
        (if has "reason" then [ (str "reason") ] else [ ])
        (if has "overlay" then [ (str "overlay") ] else [ ])
        (if has "peerSite" then [ (str "peerSite") ] else [ ])
        (if has "src" then [ (str "src") ] else [ ])
      ];
    in
    if parts == [ ] then "" else builtins.toJSON (builtins.sort (a: b: a < b) parts);

  # Check whether two route records are exact duplicates (same selection key AND same next-hop set).
  isExactDuplicate =
    a: b:
    selectionKey a == selectionKey b && nextHopSet a == nextHopSet b;

  # Check whether two route records share a selection key but differ in next-hop set.
  # This is a conflict unless multipath authority exists.
  hasConflictingNextHop =
    a: b:
    selectionKey a == selectionKey b && nextHopSet a != nextHopSet b;

  # Determine if a route has explicit multipath authority.
  # Per SMS, multipath requires both a modeled authority record and target capability.
  hasMultipathAuthority =
    r:
    (r ? multipath && builtins.isAttrs r.multipath && r.multipath ? authority)
    || (r ? intent && builtins.isAttrs r.intent && r.intent ? multipath && r.intent.multipath ? authority);

  # Collect provenance identities from a list of routes.
  # Returns the union of all provenance entries.
  collectProvenance =
    rs:
    let
      provFields = map
        (r:
          let
            p = r.provenance or null;
          in
          if p == null then [ ] else if builtins.isList p then p else [ p ]
        )
        rs;
      flat = builtins.concatLists provFields;
    in
    lib.unique flat;

in
{
  inherit
    selectionKey
    selectionKeyAttrs
    nextHopSet
    nextHopAttrs
    isExactDuplicate
    hasConflictingNextHop
    hasMultipathAuthority
    collectProvenance
    ;
}
