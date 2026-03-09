{
  description = "network-solver";

  inputs = {
    #nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixpkgs.url = "github:NixOS/nixpkgs/0182a361324364ae3f436a63005877674cf45efb";
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

      mkLib =
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          patched = import nixpkgs-network { inherit system; };
        in
        import ./src/main.nix {
          lib = pkgs.lib // {
            network = patched.lib.network;
          };
        };

      mkPkgs = system: import nixpkgs { inherit system; };

    in
    {
      lib = forAll mkLib;

      packages = forAll (
        system:
        let
          pkgs = mkPkgs system;
        in
        {
          debug = pkgs.writeShellApplication {
            name = "network-solver-debug";

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
                    solver = flake.lib."'${system}'";
                    input = builtins.fromJSON (builtins.readFile "'"$IR"'");
                  in
                    solver { inherit input; }
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
                '.meta = (.meta // {}) + { solver: { gitRev: $rev, gitDirty: $dirty } }' \
                | tee ./output-solver-signed.json \
                | ${pkgs.jq}/bin/jq -S
            '';
          };

          compile-and-solve = pkgs.writeShellApplication {
            name = "compile-and-solve";

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
          program = "${self.packages.${system}.debug}/bin/network-solver-debug";
        };

        compile-and-solve = {
          type = "app";
          program = "${self.packages.${system}.compile-and-solve}/bin/compile-and-solve";
        };
      });
    };
}
