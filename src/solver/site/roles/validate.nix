{ lib }:

{ siteName, units, roleFromInput }:

let
  unitNames = lib.attrNames units;

  missing =
    lib.filter
      (u:
        let r = roleFromInput u;
        in r == null || r == "")
      unitNames;

  rolesByUnit =
    lib.listToAttrs
      (map
        (u: {
          name = u;
          value = roleFromInput u;
        })
        unitNames);
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
    ${builtins.toJSON rolesByUnit}

    units missing roles:
    ${builtins.concatStringsSep ", " missing}
  ''
