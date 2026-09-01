{
  lib,
  self ? {
    outPath = ./.;
  },
  ...
}:

let
  policyLaneCoreDefaults = import ./policy-lane-core-defaults.nix { inherit lib self; };
  policyLaneCombinedCoreDefaults = import ./policy-lane-combined-core-defaults.nix {
    inherit lib self;
  };
in
rec {
  inherit (policyLaneCoreDefaults)
    policyLaneCoreDefaultPlan
    addPolicyLaneCoreDefaults
    ;

  inherit (policyLaneCombinedCoreDefaults)
    policyLaneCombinedCoreDefaultPlan
    addPolicyLaneCombinedCoreDefaults
    ;
}
