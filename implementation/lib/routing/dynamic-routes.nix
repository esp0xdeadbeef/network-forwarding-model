{ lib, ... }:

{
  routeUsesDynamicSource = r: (r.sourceFile or null) != null && !(r ? dst);

  dedupeDynamicRoutes =
    rs:
    (builtins.foldl'
      (acc: route:
        let
          key = builtins.toJSON route;
        in
        if acc.seen ? "${key}" then
          acc
        else
          {
            seen = acc.seen // { "${key}" = true; };
            values = acc.values ++ [ route ];
          })
      {
        seen = { };
        values = [ ];
      }
      rs).values;
}
