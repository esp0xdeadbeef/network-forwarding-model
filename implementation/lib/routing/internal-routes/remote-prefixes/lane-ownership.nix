{
  lib,
  ...
}:

# FS-260-HDS-010-SDS-010-SMS-050.
#
# A point-to-point lane address (/31, or /127 for IPv6) is directly connected
# state: it is the identity of one wire, and only the two nodes that wire joins
# can reach it. It is not derived reachability and it is not importable from a
# neighbour, so a node that is not a member of the lane's link must never carry
# a forwarding entry for it.
#
# `remote-prefixes/route-entries.nix` annotates every p2p entry with
# `laneLinkName` and `laneLinkMembers` derived from the topology endpoint that
# carries the lane. That annotation is the single authority this predicate
# consults; both the site-plan source-eligibility matrix and the legacy
# per-node remote fact table use it, so the rule is stated once.
let
  # The same lane address reaches us in two textual forms: the model's interface
  # form (`fd42:dead:beef:1000:0:0:0:0/127`) and the canonicalised form used by
  # route atoms (`fd42:dead:beef:1000:0000:0000:0000:0000/127`). Keying on the
  # raw string silently splits one lane into two, so every comparison goes
  # through this key: zero-padded, lower-case, mask preserved.
  padGroup = group: lib.fixedWidthString 4 "0" (lib.toLower group);

  laneAddressKey =
    family: address:
    let
      parts = lib.splitString "/" (toString address);
    in
    if family == 4 then
      "4|${toString address}"
    else
      let
        groups = lib.splitString ":" (builtins.head parts);
        mask = builtins.elemAt parts 1;
      in
      "6|${lib.concatStringsSep ":" (map padGroup groups)}/${mask}";

  laneMemberOf =
    entry: nodeName:
    (entry.laneLinkName or null) == null || builtins.elem nodeName (entry.laneLinkMembers or [ ]);
in
{
  inherit laneAddressKey laneMemberOf;
}
