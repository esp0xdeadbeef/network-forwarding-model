let
  repoRoot = builtins.getEnv "NFM_REPO";
  system = builtins.getEnv "NFM_SYSTEM";
  example = builtins.getEnv "NFM_EXAMPLE";
  flake = builtins.getFlake ("path:" + repoRoot);
  lib = flake.inputs.nixpkgs.lib;
  api = flake.libBySystem.${system};
  compiler = flake.inputs.network-compiler.lib.compile system;
  intent = import (repoRoot + "/tests/fixtures/examples/" + example + "/intent.nix");
  model = api.model (compiler intent);

  isLane = value: builtins.isString value && (lib.hasSuffix "/31" value || lib.hasSuffix "/127" value);

  sites = model.enterprise.esp0xdeadbeef.site or { };
  siteNames = builtins.attrNames sites;

  nodeInterfaces =
    siteName: nodeName: sites.${siteName}.nodes.${nodeName}.interfaces or { };

  # A /31 (or /127) names one wire, and its two addresses are the two ends of
  # that wire. Keying those two addresses onto the same lane is what makes
  # "which nodes are on this lane" answerable: the nodes holding either address.
  # The network address (last bit cleared) is that key, in the same padded form
  # the emitter compares with, so both sides agree.
  laneNetwork =
    address:
    let
      parts = lib.splitString "/" address;
      ipText = builtins.head parts;
      len = builtins.elemAt parts 1;
      octets = lib.splitString "." ipText;
      clearLowBit = text: lib.fixedWidthString 4 "0" (lib.toHexString ((lib.fromHexString text / 2) * 2));
    in
    if builtins.length octets == 4 && len == "31" then
      let
        last = builtins.fromJSON (builtins.elemAt octets 3);
      in
      "${builtins.elemAt octets 0}.${builtins.elemAt octets 1}.${builtins.elemAt octets 2}.${toString ((last / 2) * 2)}/31"
    else if len == "127" then
      let
        expanded = lib.splitString ":" (builtins.replaceStrings [ "::" ] [ ":0:" ] ipText);
        count = builtins.length expanded;
        padded = map (segment: lib.fixedWidthString 4 "0" (lib.toLower segment)) (lib.take (count - 1) expanded);
        lastHex = builtins.elemAt expanded (count - 1);
      in
      "${builtins.concatStringsSep ":" padded}:${clearLowBit (if lastHex == "" then "0" else lastHex)}/127"
    else
      address;

  # Every node that holds one of the two addresses of the lane. That set IS the
  # set of endpoints; nothing else is on the wire.
  lanes =
    builtins.foldl'
      (
        acc: siteName:
        builtins.foldl'
          (
            acc2: nodeName:
            let
              ifaces = nodeInterfaces siteName nodeName;
              thisNode = "${siteName}/${nodeName}";
            in
            builtins.foldl'
              (
                acc3: ifName:
                builtins.foldl'
                  (
                    acc4: address:
                    let
                      key = laneNetwork address;
                      current = acc4.${key} or [ ];
                    in
                    acc4 // { ${key} = lib.unique (current ++ [ thisNode ]); }
                  )
                  acc3
                  (builtins.filter isLane [
                    (ifaces.${ifName}.addr4 or null)
                    (ifaces.${ifName}.addr6 or null)
                  ])
              )
              acc2
              (builtins.attrNames ifaces)
          )
          acc
          (builtins.attrNames (sites.${siteName}.nodes or { }))
      )
      { }
      siteNames;

  routesOf =
    siteName: nodeName:
    builtins.concatMap
      (
        ifName:
        let
          routeSet = (nodeInterfaces siteName nodeName).${ifName}.routes or { };
        in
        map
          (route: {
            inherit ifName;
            dst = route.dst or null;
            sameInterfaceGateway = (route.via4 or null) != null && (route.via4 or null) == ((nodeInterfaces siteName nodeName).${ifName}.addr4 or null);
            via4 = route.via4 or null;
            intentKind = (route.intent or { }).kind or null;
            intentAccessNode = (route.intent or { }).accessNode or null;
          })
          ((routeSet.ipv4 or [ ]) ++ (routeSet.ipv6 or [ ]))
      )
      (builtins.attrNames (nodeInterfaces siteName nodeName));

  classify =
    siteName: nodeName:
    let
      thisNode = "${siteName}/${nodeName}";
      laneRoutes = builtins.filter (r: isLane r.dst) (routesOf siteName nodeName);
    in
    builtins.concatMap
      (
        route:
        let
          laneEndpoints = lanes.${laneNetwork route.dst} or [ ];
          onLane = builtins.elem thisNode laneEndpoints;
        in
        if laneEndpoints == [ ] then
          # A lane nobody advertises: the topology is inconsistent.
          [ (route // { inherit siteName nodeName thisNode; kindOf = "unknown-lane"; realEndpoints = [ ]; }) ]
        else if onLane && route.via4 != null then
          [ (route // { inherit siteName nodeName thisNode; kindOf = "endpoint-with-gateway"; realEndpoints = laneEndpoints; }) ]
        else if onLane then
          [ ]
        else
          [ (route // { inherit siteName nodeName thisNode; kindOf = "not-on-lane"; realEndpoints = laneEndpoints; }) ]
      )
      laneRoutes;

  violations = builtins.concatMap (
    siteName: builtins.concatMap (nodeName: classify siteName nodeName) (builtins.attrNames (sites.${siteName}.nodes or { }))
  ) siteNames;
in
{
  inherit example;
  violationCount = builtins.length violations;
  violations = if builtins.length violations > 25 then builtins.genList (i: builtins.elemAt violations i) 25 else violations;
}
