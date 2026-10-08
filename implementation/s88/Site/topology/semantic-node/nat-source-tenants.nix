# FS-322/FS-380: resolve which tenants egress through a given uplink from the
# access scopes' `selects`, shared by the NAT44 and NAT66 egress modules.
#
# Reachability is a scope property: an access declares the exits it may use with
# `selects`, and the tenant is attached to that access. A tenant egressing
# through an uplink is therefore the tenant attached to an access whose
# `selects` resolves to that uplink, whether or not a relation pins the exit.
{ lib, sortedUnique, listOrEmpty, attrsOrEmpty }:

let
  topologyNodesFor =
    site:
    attrsOrEmpty ((attrsOrEmpty (site.topology or null)).nodes or null)
    // attrsOrEmpty (site.nodes or null);
in
{
  make =
    { site }:
    let
      topologyNodes = topologyNodesFor site;
      nodeUplinkNames =
        nodeName:
        builtins.attrNames (
          attrsOrEmpty ((attrsOrEmpty (topologyNodes.${nodeName} or null)).uplinks or null)
        );
      selectUplinkNames =
        entry:
        if builtins.isString entry then
          [ entry ]
        else if builtins.isAttrs entry then
          let
            e = attrsOrEmpty entry;
          in
          if (e.uplink or null) != null then
            [ (toString e.uplink) ]
          else if (e.surface or null) != null then
            [ (toString e.surface) ]
          else if (e.scope or null) != null then
            nodeUplinkNames (toString e.scope)
          else
            [ ]
        else
          [ ];
      selectsUplinks =
        node:
        let
          sel = (attrsOrEmpty node).selects or [ ];
        in
        if builtins.isList sel then lib.concatMap selectUplinkNames sel else [ ];
      tenantsAttachedToUplink =
        uplinkName:
        sortedUnique (
          builtins.filter (name: name != "") (
            builtins.concatMap (
              nodeName:
              let
                node = attrsOrEmpty (topologyNodes.${nodeName} or null);
              in
              if builtins.elem uplinkName (selectsUplinks node) then
                map (a: toString (a.name or "")) (
                  builtins.filter (a: builtins.isAttrs a && (a.kind or null) == "tenant") (
                    listOrEmpty (node.attachments or null)
                  )
                )
              else
                [ ]
            ) (builtins.attrNames topologyNodes)
          )
        );
    in
    {
      inherit
        topologyNodes
        nodeUplinkNames
        selectUplinkNames
        selectsUplinks
        tenantsAttachedToUplink
        ;
    };
}
