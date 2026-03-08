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
    network-solver: missing required node role(s)

    site: ${siteName}

    nodes:
    ${builtins.toJSON nodes}

    inferredRoles:
    ${builtins.toJSON (builtins.mapAttrs (_: roleFromInput) nodes)}

    nodes missing roles:
    ${builtins.concatStringsSep ", " missing}
  ''
