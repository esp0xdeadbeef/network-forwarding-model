{ lib, self ? { outPath = ./.; }, ... }:

let
  helpers = import ./static-helpers.nix { inherit lib self; };
in
{
  apply =
    { node
    , routeContext
    ,
    }:
    let
      inherit (routeContext) mkRoute4 mkRoute6;

      ifs = node.interfaces or { };
      ifNames = builtins.attrNames ifs;

      routesForInterface =
        ifName: iface:
        let
          uplinkName = toString (iface.upstream or (iface.uplink or ifName));
          learnedIntent = dst: {
            kind = "uplink-learned-reachability";
            source = "explicit-uplink";
            routeSource = "explicit-uplink";
            sourcePeerOrProvider = uplinkName;
            routePurpose = if dst == helpers.default4 || dst == helpers.default6 then "wan-internet" else "provider-prefix";
            maximumScope = "provider";
            rejectionBehavior = "reject";
            routeAvailabilityOnly = true;
            policyAuthority = false;
          };
          prefixRoutes4 =
            if (iface.peerAddr4 or null) == null then
              [ ]
            else
              map
                (
                  dst:
                  mkRoute4 {
                    inherit dst;
                    via4 = helpers.stripMask iface.peerAddr4;
                    proto = "uplink";
                    intentKind = "uplink-learned-reachability";
                    intent = learnedIntent dst;
                  }
                )
                (iface.uplinkRoutes4 or [ ]);

          prefixRoutes6 =
            if (iface.peerAddr6 or null) == null then
              [ ]
            else
              map
                (
                  dst:
                  mkRoute6 {
                    inherit dst;
                    via6 = helpers.stripMask iface.peerAddr6;
                    proto = "uplink";
                    intentKind = "uplink-learned-reachability";
                    intent = learnedIntent dst;
                  }
                )
                (iface.uplinkRoutes6 or [ ]);

          default4 =
            if
              (iface.kind or null) == "wan" && (iface.gateway or false) && (iface.peerAddr4 or null) != null
            then
              [
                (mkRoute4 {
                  dst = helpers.default4;
                  via4 = helpers.stripMask iface.peerAddr4;
                  proto = "default";
                  intentKind = "default-reachability";
                })
              ]
            else
              [ ];

          default6 =
            if
              (iface.kind or null) == "wan" && (iface.gateway or false) && (iface.peerAddr6 or null) != null
            then
              [
                (mkRoute6 {
                  dst = helpers.default6;
                  via6 = helpers.stripMask iface.peerAddr6;
                  proto = "default";
                  intentKind = "default-reachability";
                })
              ]
            else
              [ ];
        in
        {
          routes4 = prefixRoutes4 ++ default4;
          routes6 = prefixRoutes6 ++ default6;
        };
    in
    builtins.foldl'
      (
        acc: ifName:
        let
          routes = routesForInterface ifName ifs.${ifName};
        in
        if routes.routes4 == [ ] && routes.routes6 == [ ] then
          acc
        else
          helpers.addRoutesOnLink acc ifName routes.routes4 routes.routes6
      )
      node
      ifNames;
}
