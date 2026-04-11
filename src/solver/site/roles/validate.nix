{ lib }:
{
  siteName,
  nodes,
  roleFromInput,
}:

let
  missing = lib.filter (
    n:
    let
      r = roleFromInput n;
    in
    r == null || r == ""
  ) (builtins.attrNames nodes);
in
if missing == [ ] then
  true
else
  throw ''
    network-forwarding-model: missing required node role(s)

    site: ${siteName}

    nodes:
    ${builtins.toJSON nodes}

    inferredRoles:
    ${builtins.toJSON (builtins.mapAttrs (name: _: roleFromInput name) nodes)}

    nodes missing roles:
    ${builtins.concatStringsSep ", " missing}
  ''
