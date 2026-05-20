{ lib, ... }:

{
  build =
    { allUnits
    , graph
    , roleFromInput
    ,
    }:
    let
      sortedStrings = xs: lib.sort (a: b: a < b) (lib.unique (map toString xs));

      chainIndexOf =
        nodeName:
        let
          hits = lib.filter (x: x.value == nodeName) (lib.imap0 (idx: value: { inherit idx value; }) graph.chain);
        in
        if hits == [ ] then null else (builtins.head hits).idx;
    in
    builtins.listToAttrs (
      map
        (
          unitName0:
          let
            unitName = toString unitName0;
            role = roleFromInput unitName;
            incoming = sortedStrings (map (e: e.a) (graph.insOf unitName));
            outgoing = sortedStrings (map (e: e.b) (graph.outsOf unitName));
            participates = lib.elem unitName graph.nodes;
            accessTermination = role == "access";
            policyEnforcement = role == "policy";
            transitForwarding = participates || builtins.elem role [
              "core"
              "policy"
              "downstream-selector"
              "upstream-selector"
            ];
            transitRoutingAuthority = builtins.elem role [
              "core"
              "policy"
              "downstream-selector"
              "upstream-selector"
            ];
            upstreamSelectionAuthority = role == "upstream-selector";
          in
          {
            name = unitName;
            value = {
              inherit role;
              functions = lib.sort (a: b: a < b) (
                lib.unique (
                  (lib.optional accessTermination "access-gateway")
                  ++ (lib.optional policyEnforcement "policy-enforcement")
                  ++ (lib.optional (role == "downstream-selector") "downstream-selection")
                  ++ (lib.optional transitForwarding "transit-forwarder")
                  ++ (lib.optional (role == "core") "routing-core")
                  ++ (lib.optional upstreamSelectionAuthority "upstream-selection")
                )
              );
              traversal = {
                inherit participates incoming outgoing;
                chainIndex = chainIndexOf unitName;
                entry = participates && incoming == [ ];
                terminal = participates && outgoing == [ ];
              };
              responsibilities = {
                inherit accessTermination policyEnforcement transitForwarding;
              };
              authority = {
                attachedPrefixRouting = accessTermination;
                transitRouting = transitRoutingAuthority;
                upstreamSelection = upstreamSelectionAuthority;
              };
            };
          }
        )
        allUnits
    );
}
