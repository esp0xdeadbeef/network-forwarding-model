{
  description = "network-forwarding-model";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-network.url = "github:NixOS/nixpkgs/ac56c456ebe4901c561d3ebf1c98fbd970aea753";
    network-compiler.url = "github:esp0xdeadbeef/network-compiler";
    network-compiler.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-network,
      network-compiler,
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
          pkgs = mkPkgs system;
          patched = import nixpkgs-network { inherit system; };

          applyForwardingModel = import ./src/main.nix {
            lib = pkgs.lib // {
              network = patched.lib.network;
            };
          };

          compilerLib =
            if network-compiler ? libBySystem then
              network-compiler.libBySystem.${system}
            else
              {
                compile = network-compiler.lib.compile system;
                compilePath = valueOrPath: (network-compiler.lib.compile system) (readValue valueOrPath);
              };
        in
        rec {
          model = input: applyForwardingModel { inherit input; };

          readInput = readValue;

          build = { input }: model input;

          buildFromCompilerInputs =
            { input }:
            build {
              input = compilerLib.compile input;
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

              [ $

              IR="$1"

              json="$(
                nix eval --impure --json --expr '
                  let
                    flake = builtins.getFlake (toString ${self});
                    forwardingModel = flake.lib."'${system}'";
                    input = builtins.fromJSON (builtins.readFile "'"$IR"'");
                  in
                    forwardingModel { inherit input; }
                '
              )"

              gitRev="$(${pkgs.git}/bin/git rev-parse HEAD 2>/dev/null || echo "unknown")"

              if ${pkgs.git}/bin/git diff --quiet && ${pkgs.git}/bin/git diff --cached --quiet; then
                gitDirty=false
              else
                gitDirty=true
              fi

              echo "$json" | ${pkgs.jq}/bin/jq -S -c \
                --arg rev "$gitRev" \
                --argjson dirty "$gitDirty" \
                '.meta = (.meta // {}) | .meta.networkForwardingModel = ((.meta.networkForwardingModel // {}) + { gitRev: $rev, gitDirty: $dirty })' \
                | tee ./output-network-forwarding-model-signed.json \
                | ${pkgs.jq}/bin/jq -S
            '';
          };

          compile-and-build-forwarding-model = pkgs.writeShellApplication {
            name = "compile-and-build-forwarding-model";

            runtimeInputs = [
              pkgs.jq
              pkgs.nix
            ];

            text = ''
              set -euo pipefail

              [ $

              INPUTS_NIX="$1"

              IR_JSON="$(mktemp)"
              trap 'rm -f "$IR_JSON"' EXIT

              nix run --no-warn-dirty ${network-compiler}#compile -- "$INPUTS_NIX" > "$IR_JSON"

              nix run ${self}#debug -- "$IR_JSON"
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
