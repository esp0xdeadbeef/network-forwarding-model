{
  description = "network-forwarding-model";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-network.url = "github:NixOS/nixpkgs/ac56c456ebe4901c561d3ebf1c98fbd970aea753";
    network-compiler.url = "github:esp0xdeadbeef/network-compiler";
    network-compiler.inputs.nixpkgs.follows = "nixpkgs";
    network-compiler.inputs.network-labs.follows = "network-labs";
    network-labs.url = "github:esp0xdeadbeef/network-labs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-network,
      network-compiler,
      network-labs,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAll = f: nixpkgs.lib.genAttrs systems f;

      readValue =
        valueOrPath:
        if builtins.isPath valueOrPath then
          readValue (builtins.toString valueOrPath)
        else if builtins.isString valueOrPath then
          if valueOrPath == "" then
            { }
          else if builtins.match ".*\\.json$" valueOrPath != null then
            builtins.fromJSON (builtins.readFile valueOrPath)
          else
            let
              value = import valueOrPath;
            in
            if builtins.isFunction value then value { } else value
        else if builtins.isFunction valueOrPath then
          valueOrPath { }
        else
          valueOrPath;

      mkPkgs = system: import nixpkgs { inherit system; };

      mkSystemLib =
        system:
        let
          applyForwardingModel = import ./s88/build.nix {
            inherit self;
            lib = nixpkgs.lib // {
              network = nixpkgs-network.lib.network;
            };
          };

          normalizeModelInput =
            value:
            if builtins.isAttrs value && value ? input && !(value ? sites) && !(value ? enterprise) then
              value.input
            else
              value;

          isCompilerOutput =
            value:
            builtins.isAttrs value && value ? sites && builtins.isAttrs value.sites && !(value ? enterprise);

          compilerLib =
            if network-compiler ? libBySystem then
              network-compiler.libBySystem.${system}
            else
              {
                compile = network-compiler.lib.compile system;
                compilePath = valueOrPath: (network-compiler.lib.compile system) (readValue valueOrPath);
              };

          controlledSkip = import ./lib/controlled-skip.nix {
            repository = "network-forwarding-model";
            repositoryRevision = self.sourceInfo.rev or self.dirtyRev or "uncommitted";
            stageIndex = 2;
            previousStage = "network-compiler";
            nextStage = "network-control-plane-model";
            normalInputContract = "network-forwarding-model-input/v1";
          };

          layerEntrySkippedForBoundary = {
            intent-source = [ ];
            compiler-output = [ "intent-source" ];
            forwarding-model-input = [
              "intent-source"
              "network-compiler"
            ];
            control-plane-input = [
              "intent-source"
              "network-compiler"
              "network-forwarding-model"
            ];
            renderer-input = [
              "intent-source"
              "network-compiler"
              "network-forwarding-model"
              "network-control-plane-model"
            ];
            runtime-artifact = [
              "intent-source"
              "network-compiler"
              "network-forwarding-model"
              "network-control-plane-model"
              "renderer"
            ];
          };

          layerEntryWarningBySkippedLayer = {
            intent-source = "WARN_LAYER_ENTRY_SKIPS_NETWORK_LABS_INTENT_SOURCE";
            network-compiler = "WARN_LAYER_ENTRY_SKIPS_NETWORK_COMPILER";
            network-forwarding-model = "WARN_LAYER_ENTRY_SKIPS_NFM";
            network-control-plane-model = "WARN_LAYER_ENTRY_SKIPS_CPM";
            renderer = "WARN_LAYER_ENTRY_SKIPS_RENDERER";
          };

          layerEntryCurrentRepo = "network-forwarding-model";

          layerEntrySkippedLayers =
            entryBoundary:
            layerEntrySkippedForBoundary.${entryBoundary}
              or (throw "network-forwarding-model layer-entry warning: unknown entryBoundary '${entryBoundary}'");

          layerEntryWarningFor = layer: {
            code = layerEntryWarningBySkippedLayer.${layer};
            severity = "warning";
            skippedLayer = layer;
            issuingRepo = layer;
            message =
              if layer == layerEntryCurrentRepo then
                "layer-entry starts below network-forwarding-model; NFM execution and validation are not covered by this scenario"
              else
                "layer-entry skips ${layer}; that layer is not covered by this scenario";
          };
        in
        rec {
          model = inputOrArgs: applyForwardingModel { input = normalizeModelInput inputOrArgs; };

          inherit controlledSkip;

          controlledSkipAcknowledgement = controlledSkip.acknowledge;

          readInput = readValue;

          layerEntryWarnings =
            {
              entryBoundary ? "intent-source",
            }:
            let
              skippedUpstreamLayers = layerEntrySkippedLayers entryBoundary;
              repoSkipped = builtins.elem layerEntryCurrentRepo skippedUpstreamLayers;
              warnings = if repoSkipped then [ (layerEntryWarningFor layerEntryCurrentRepo) ] else [ ];
            in
            {
              repo = layerEntryCurrentRepo;
              inherit
                entryBoundary
                skippedUpstreamLayers
                repoSkipped
                warnings
                ;
              inputTreatment = if repoSkipped then "pass-through" else "consume-or-normalize";
            };

          layerEntryEnvelope =
            {
              input,
              entryBoundary ? "intent-source",
            }:
            let
              payload = readValue input;
              warningPayload = layerEntryWarnings { inherit entryBoundary; };
            in
            warningPayload
            // {
              normalizedTo = "nix-attrset";
              input = payload;
              output = payload;
            };

          build = args: model args;

          buildFromCompilerInputs =
            args:
            let
              normalized = normalizeModelInput args;
            in
            build {
              input = if isCompilerOutput normalized then normalized else compilerLib.compile normalized;
            };

          buildFromCompilerInputPath =
            valueOrPath:
            buildFromCompilerInputs {
              input = readValue valueOrPath;
            };

          writeJSON =
            {
              input,
              name ? "output-network-forwarding-model.json",
            }:
            let
              pkgs = mkPkgs system;
            in
            pkgs.writeText name (
              builtins.toJSON (build {
                inherit input;
              })
            );

          writeFromCompilerInputPath =
            {
              path,
              name ? "output-network-forwarding-model.json",
            }:
            let
              pkgs = mkPkgs system;
            in
            pkgs.writeText name (builtins.toJSON (buildFromCompilerInputPath path));
        };

    in
    {
      lib = forAll (system: (mkSystemLib system).model);

      libBySystem = forAll mkSystemLib;

      packages = forAll (
        system:
        let
          pkgs = mkPkgs system;
        in
        {
          debug = pkgs.writeShellApplication {
            name = "network-forwarding-model-debug";

            runtimeInputs = [
              pkgs.jq
              pkgs.git
              pkgs.nix
              pkgs.coreutils
            ];

            text = ''
              set -euo pipefail

              [ $# -ge 1 ] || { echo "usage: nix run path:${self.outPath}#debug -- <ir.json>" >&2; exit 1; }

              IR="$1"
              tmpdir="$(mktemp -d)"
              trap 'rm -rf "$tmpdir"' EXIT

              json="$(
                nix eval --impure --json --expr '
                  let
                    system = "'${system}'";
                    pkgs = import ${nixpkgs} { inherit system; };
                    patched = import ${nixpkgs-network} { inherit system; };

                    applyForwardingModel = import ${self.outPath}/s88/build.nix {
                      self = { outPath = ${self.outPath}; };
                      lib = pkgs.lib // {
                        network = patched.lib.network;
                      };
                    };

                    input = builtins.fromJSON (builtins.readFile "'"$IR"'");
                  in
                    applyForwardingModel { inherit input; }
                '
              )"

              gitRev="unknown"
              gitDirty=true
              repoRoot="$(${pkgs.git}/bin/git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
              repoRemote=""
              if [[ -n "$repoRoot" ]]; then
                repoRemote="$(${pkgs.git}/bin/git -C "$repoRoot" config --get remote.origin.url 2>/dev/null || true)"
              fi
              if [[ -n "$repoRoot" && ( "''${repoRoot##*/}" == "network-forwarding-model" || "$repoRemote" == *"network-forwarding-model"* ) ]]; then
                gitRev="$(${pkgs.git}/bin/git -C "$repoRoot" rev-parse HEAD 2>/dev/null || echo "unknown")"
                if ${pkgs.git}/bin/git -C "$repoRoot" diff --quiet >/dev/null 2>&1 && ${pkgs.git}/bin/git -C "$repoRoot" diff --cached --quiet >/dev/null 2>&1; then
                  gitDirty=false
                else
                  gitDirty=true
                fi
              fi
              sourceNarHash="${self.sourceInfo.narHash or ""}"
              sourceLastModified="${toString (self.sourceInfo.lastModified or self.lastModified or 0)}"

              echo "$json" | ${pkgs.jq}/bin/jq -S -c \
                --arg rev "$gitRev" \
                --argjson dirty "$gitDirty" \
                --arg sourceNarHash "$sourceNarHash" \
                --arg sourceLastModified "$sourceLastModified" \
                '.meta = (.meta // {}) | .meta.networkForwardingModel = ((.meta.networkForwardingModel // {}) + {
                  gitRev: $rev,
                  gitDirty: $dirty,
                  sourceNarHash: $sourceNarHash,
                  sourceLastModified: $sourceLastModified
                })' \
                | tee "$tmpdir/output-network-forwarding-model-signed.json" \
                | tee >(${pkgs.jq}/bin/jq -r '.meta.networkForwardingModel.warningMessages[]? | "WARNING: " + .' >&2) \
                | ${pkgs.jq}/bin/jq -S
            '';
          };

          compile-and-build-forwarding-model = pkgs.writeShellApplication {
            name = "compile-and-build-forwarding-model";

            runtimeInputs = [
              pkgs.git
              pkgs.jq
              pkgs.nix
            ];

            text = ''
              set -euo pipefail

              [ $# -ge 1 ] || { echo "usage: nix run path:${self.outPath}#compile-and-build-forwarding-model -- <compiler-inputs.nix>" >&2; exit 1; }

              INPUTS_NIX="$1"

              json="$(
                nix eval --impure --json --expr '
                  let
                    system = "'${system}'";
                    nfm = builtins.getFlake "path:${self.outPath}";
                  in
                    nfm.libBySystem.${system}.buildFromCompilerInputPath "'"$INPUTS_NIX"'"
                '
              )"

              gitRev="unknown"
              gitDirty=true
              repoRoot="$(${pkgs.git}/bin/git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
              repoRemote=""
              if [[ -n "$repoRoot" ]]; then
                repoRemote="$(${pkgs.git}/bin/git -C "$repoRoot" config --get remote.origin.url 2>/dev/null || true)"
              fi
              if [[ -n "$repoRoot" && ( "''${repoRoot##*/}" == "network-forwarding-model" || "$repoRemote" == *"network-forwarding-model"* ) ]]; then
                gitRev="$(${pkgs.git}/bin/git -C "$repoRoot" rev-parse HEAD 2>/dev/null || echo "unknown")"
                if ${pkgs.git}/bin/git -C "$repoRoot" diff --quiet >/dev/null 2>&1 && ${pkgs.git}/bin/git -C "$repoRoot" diff --cached --quiet >/dev/null 2>&1; then
                  gitDirty=false
                else
                  gitDirty=true
                fi
              fi
              sourceNarHash="${self.sourceInfo.narHash or ""}"
              sourceLastModified="${toString (self.sourceInfo.lastModified or self.lastModified or 0)}"

              echo "$json" | ${pkgs.jq}/bin/jq -S -c \
                --arg rev "$gitRev" \
                --argjson dirty "$gitDirty" \
                --arg sourceNarHash "$sourceNarHash" \
                --arg sourceLastModified "$sourceLastModified" \
                '.meta = (.meta // {}) | .meta.networkForwardingModel = ((.meta.networkForwardingModel // {}) + {
                  gitRev: $rev,
                  gitDirty: $dirty,
                  sourceNarHash: $sourceNarHash,
                  sourceLastModified: $sourceLastModified
                })' \
                | tee >(${pkgs.jq}/bin/jq -r '.meta.networkForwardingModel.warningMessages[]? | "WARNING: " + .' >&2) \
                | ${pkgs.jq}/bin/jq -S
            '';
          };

          default = self.packages.${system}.debug;
        }
      );

      apps = forAll (system: {
        debug = {
          type = "app";
          program = "${self.packages.${system}.debug}/bin/network-forwarding-model-debug";
        };

        compile-and-build-forwarding-model = {
          type = "app";
          program = "${
            self.packages.${system}.compile-and-build-forwarding-model
          }/bin/compile-and-build-forwarding-model";
        };
      });
    };
}
