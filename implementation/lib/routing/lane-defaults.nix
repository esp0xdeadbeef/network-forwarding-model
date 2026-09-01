{
  lib,
  self ? {
    outPath = ./.;
  },
  ...
}:

let
  downstreamSelectorDefaults = import ./downstream-selector-defaults.nix { inherit lib self; };
  policyUpstreamSelectorDefaults = import ./policy-upstream-selector-defaults.nix {
    inherit lib self;
  };
  policyUpstreamSelectorCombinedDefaults = import ./policy-upstream-selector-combined-defaults.nix {
    inherit lib self;
  };
  upstreamSelectorLaneDefaults = import ./upstream-selector-lane-defaults.nix { inherit lib self; };
in
rec {
  inherit (downstreamSelectorDefaults)
    downstreamSelectorPolicyDefaultPlan
    addDownstreamSelectorPolicyDefaults
    ;

  inherit (policyUpstreamSelectorDefaults)
    policyUpstreamSelectorDefaultPlan
    addPolicyUpstreamSelectorDefaults
    ;

  inherit (policyUpstreamSelectorCombinedDefaults)
    policyUpstreamSelectorCombinedDefaultPlan
    addPolicyUpstreamSelectorCombinedDefaults
    ;

  inherit (upstreamSelectorLaneDefaults)
    addPolicyLaneCoreDefaults
    addPolicyLaneCombinedCoreDefaults
    policyLaneCoreDefaultPlan
    ;

  addUpstreamSelectorPolicyLaneCoreDefaults = upstreamSelectorLaneDefaults.addPolicyLaneCoreDefaults;
  addUpstreamSelectorPolicyCombinedCoreDefaults =
    upstreamSelectorLaneDefaults.addPolicyLaneCombinedCoreDefaults;
}
