{
  lib,
  ulaPrefix,
  tenantV4Base,
}:

topoRaw:

let
  links = topoRaw.links or { };
  nodes0 = topoRaw.nodes or { };

  coreFabricNodeName = topoRaw.coreNodeName or null;

  membersOf = l: lib.unique ((l.members or [ ]) ++ (builtins.attrNames (l.endpoints or { })));

  endpointsOf = l: l.endpoints or { };

  chooseEndpointKey =
    linkName: l: nodeName:
    let
      eps = endpointsOf l;
      keys = builtins.attrNames eps;

      exact = if eps ? "${nodeName}" then nodeName else null;

      byLinkName = "${nodeName}-${linkName}";
      byLink = if eps ? "${byLinkName}" then byLinkName else null;

      bySemanticName =
        let
          nm = l.name or null;
          k = if nm == null then null else "${nodeName}-${nm}";
        in
        if k != null && eps ? "${k}" then k else null;

      parts = lib.splitString "-" nodeName;
      lastPart = if parts == [ ] then "" else lib.last parts;

      hasNumericSuffix = builtins.match "^[0-9]+$" lastPart != null;

      baseName =
        if hasNumericSuffix && (lib.length parts) > 1 then
          lib.concatStringsSep "-" (lib.init parts)
        else
          null;

      byBaseSuffix = if baseName != null && eps ? "${baseName}" then baseName else null;

      pref = "${nodeName}-";
      prefKeys = lib.filter (k: lib.hasPrefix pref k) keys;

      bySinglePrefix = if lib.length prefKeys == 1 then lib.head prefKeys else null;

      bySortedPrefix = if prefKeys == [ ] then null else lib.head (lib.sort (a: b: a < b) prefKeys);
    in
    if exact != null then
      exact
    else if byLink != null then
      byLink
    else if bySemanticName != null then
      bySemanticName
    else if byBaseSuffix != null then
      byBaseSuffix
    else if bySinglePrefix != null then
      bySinglePrefix
    else
      bySortedPrefix;

  getEp =
    linkName: l: nodeName:
    let
      k = chooseEndpointKey linkName l nodeName;
      eps = endpointsOf l;
    in
    if k == null then { } else (eps.${k} or { });

  mkIface =
    linkName: l: nodeName:
    let
      ep = getEp linkName l nodeName;
    in
    {
      kind = l.kind or null;
      carrier = l.carrier or "lan";

      tenant = ep.tenant or null;
      gateway = ep.gateway or false;
      export = ep.export or false;

      addr4 = ep.addr4 or null;
      addr6 = ep.addr6 or null;
      addr6Public = ep.addr6Public or null;

      routes4 = ep.routes4 or [ ];
      routes6 = ep.routes6 or [ ];
      ra6Prefixes = ep.ra6Prefixes or [ ];

      acceptRA = ep.acceptRA or false;
      dhcp = ep.dhcp or false;
    };

  linkNamesForNode =
    nodeName:
    lib.filter (
      lname:
      let
        l = links.${lname};
        k = chooseEndpointKey lname l nodeName;
      in
      (lib.elem nodeName (membersOf l)) || (k != null)
    ) (lib.attrNames links);

  interfacesForNode =
    nodeName:
    lib.listToAttrs (
      map (lname: {
        name = lname;
        value = mkIface lname links.${lname} nodeName;
      }) (linkNamesForNode nodeName)
    );

  endpointNodes = lib.unique (
    lib.concatMap (l: builtins.attrNames (l.endpoints or { })) (lib.attrValues links)
  );

  tenantVids = lib.unique (
    lib.filter (x: x != null) (
      lib.concatMap (
        l:
        lib.concatMap (
          ep:
          let
            t = ep.tenant or null;
          in
          [ ]
        ) (lib.attrValues (l.endpoints or { }))
      ) (lib.attrValues links)
    )
  );

  isNonNumericLast =
    n:
    let
      ps = lib.splitString "-" n;
      last = if ps == [ ] then "" else lib.last ps;
    in
    builtins.match "^[0-9]+$" last == null;

  coreCtxBases = lib.filter (
    n: coreFabricNodeName != null && lib.hasPrefix "${coreFabricNodeName}-" n && isNonNumericLast n
  ) endpointNodes;

  mkTenantCtxNodes =
    base:
    let
      ctx = lib.removePrefix "${coreFabricNodeName}-" base;
    in
    map (
      vid:
      let
        name = "${coreFabricNodeName}-${ctx}-${toString vid}";
      in
      if nodes0 ? "${name}" then
        null
      else
        {
          inherit name;
          value = {
            ifs = nodes0.${coreFabricNodeName}.ifs;
          };
        }
    ) tenantVids;

  mkMissingNode =
    n:
    if nodes0 ? "${n}" then
      null
    else if
      coreFabricNodeName != null
      && lib.hasPrefix "${coreFabricNodeName}-" n
      && nodes0 ? "${coreFabricNodeName}"
      && (nodes0.${coreFabricNodeName} ? ifs)
    then
      {
        name = n;
        value = {
          ifs = nodes0.${coreFabricNodeName}.ifs;
        };
      }
    else
      {
        name = n;
        value = {
          ifs = {
            lan = "lan";
          };
        };
      };

  missingFromEndpoints = lib.filter (x: x != null) (map mkMissingNode endpointNodes);

  tenantCtxNodes =
    if
      coreFabricNodeName != null
      && nodes0 ? "${coreFabricNodeName}"
      && (nodes0.${coreFabricNodeName} ? ifs)
      && tenantVids != [ ]
    then
      lib.filter (x: x != null) (lib.concatMap mkTenantCtxNodes coreCtxBases)
    else
      [ ];

  missingNodes = missingFromEndpoints ++ tenantCtxNodes;

  nodes1 = nodes0 // (lib.listToAttrs missingNodes);

  nodes' = lib.mapAttrs (
    n: node:
    node
    // {
      interfaces = interfacesForNode n;
    }
  ) nodes1;

in
topoRaw
// {
  inherit ulaPrefix tenantV4Base;
  nodes = nodes';
}
