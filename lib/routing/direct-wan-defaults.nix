{ lib }:

let
  helpers = import ./static-helpers.nix { inherit lib; };
in
{
  apply =
    {
      node,
      mkRoute4,
      mkRoute6,
    }:
    let
      ifs = node.interfaces or { };
      ifNames = builtins.attrNames ifs;

      routesForInterface =
        iface:
        let
          prefixRoutes4 =
            if (iface.peerAddr4 or null) == null then
              [ ]
            else
              map (
                dst:
                mkRoute4 {
                  inherit dst;
                  via4 = helpers.stripMask iface.peerAddr4;
                  proto = "uplink";
                  intentKind = "uplink-learned-reachability";
                }
              ) (iface.uplinkRoutes4 or [ ]);

          prefixRoutes6 =
            if (iface.peerAddr6 or null) == null then
              [ ]
            else
              map (
                dst:
                mkRoute6 {
                  inherit dst;
                  via6 = helpers.stripMask iface.peerAddr6;
                  proto = "uplink";
                  intentKind = "uplink-learned-reachability";
                }
              ) (iface.uplinkRoutes6 or [ ]);

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
            else if
              (iface.kind or null) == "wan" && (iface.gateway or false) && (iface.addr4 or null) != null
            then
              [
                {
                  dst = helpers.default4;
                  proto = "default";
                  intent = {
                    kind = "default-reachability";
                  };
                }
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
            else if
              (iface.kind or null) == "wan" && (iface.gateway or false) && (iface.addr6 or null) != null
            then
              [
                {
                  dst = helpers.default6;
                  proto = "default";
                  intent = {
                    kind = "default-reachability";
                  };
                }
              ]
            else
              [ ];
        in
        {
          routes4 = prefixRoutes4 ++ default4;
          routes6 = prefixRoutes6 ++ default6;
        };
    in
    builtins.foldl' (
      acc: ifName:
      let
        routes = routesForInterface ifs.${ifName};
      in
      if routes.routes4 == [ ] && routes.routes6 == [ ] then
        acc
      else
        helpers.addRoutesOnLink acc ifName routes.routes4 routes.routes6
    ) node ifNames;
}
