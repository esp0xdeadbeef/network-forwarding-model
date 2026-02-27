{
  description = "network-solver";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    network-compiler.url = "github:esp0xdeadbeef/network-compiler";
    network-compiler.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, network-compiler }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      packages = forAll (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in {

          debug = pkgs.writeShellApplication {
            name = "network-solver-debug";
            runtimeInputs = [ pkgs.jq ];

            text = ''
              set -euo pipefail

              if [ $# -lt 1 ]; then
                echo "usage: nix run ${self}#debug -- <ir.json>" >&2
                exit 1
              fi

              IR="$1"

              nix eval --impure --json --expr '
                let
                  pkgs = import ${nixpkgs} { system = "'${system}'"; };
                  lib = pkgs.lib;

                  # IMPORTANT: import from flake store path, NOT cwd
                  solver = import ${self} { inherit lib; };

                  input = builtins.fromJSON (builtins.readFile "'"$IR"'");
                in
                  solver { inherit input; }
              ' | jq
            '';
          };

          compile-and-solve = pkgs.writeShellApplication {
            name = "compile-and-solve";
            runtimeInputs = [ pkgs.jq ];

            text = ''
              set -euo pipefail

              if [ $# -lt 1 ]; then
                echo "usage: nix run ${self}#compile-and-solve -- <compiler-inputs.nix>" >&2
                exit 1
              fi

              INPUTS_NIX="$1"
              IR_JSON="$(mktemp)"

              nix run --no-warn-dirty \
                ${network-compiler}#compile -- \
                "$INPUTS_NIX" > "$IR_JSON"

              nix run ${self}#debug -- "$IR_JSON"
            '';
          };

          default = self.packages.${system}.debug;
        });

      apps = forAll (system: {
        debug = {
          type = "app";
          program =
            "${self.packages.${system}.debug}/bin/network-solver-debug";
        };

        compile-and-solve = {
          type = "app";
          program =
            "${self.packages.${system}.compile-and-solve}/bin/compile-and-solve";
        };
      });
    };
}
