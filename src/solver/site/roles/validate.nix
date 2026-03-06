{ lib }:
{ siteName, units, roleFromInput }:

let
  missing = lib.filter (u: let r = roleFromInput u; in r == null || r == "") (builtins.attrNames units);
in
if missing == [ ] then
  true
else
  throw ''
    network-solver: missing required unit role(s)

    site: ${siteName}

    units:
    ${builtins.toJSON units}

    inferredRoles:
    ${builtins.toJSON (builtins.mapAttrs (_: roleFromInput) units)}

    units missing roles:
    ${builtins.concatStringsSep ", " missing}
  ''
