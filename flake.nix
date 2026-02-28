# ./flake.nix
{
  description = "network-solver";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Match network-compiler's pinned lib.network
    nixpkgs-network.url = "github:NixOS/nixpkgs/ac56c456ebe4901c561d3ebf1c98fbd970aea753";

    network-compiler.url = "github:esp0xdeadbeef/network-compiler";
    network-compiler.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nixpkgs-network, network-compiler }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      # Expose solver as flake lib entrypoint with patched lib.network
      lib = forAll (system:
        let
          pkgs = import nixpkgs { inherit system; };
          patchedPkgs = import nixpkgs-network { inherit system; };

          lib =
            pkgs.lib // {
              network = patchedPkgs.lib.network;
            };
        in
          import ./src/main.nix { inherit lib; }
      );

      packages = forAll (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
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
                  flake = builtins.getFlake (toString ${self});
                  solver = flake.lib."'${system}'";

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

              cleanup() {
                if [ -n "''${IR_JSON:-}" ] && [ -f "''${IR_JSON:-}" ]; then
                  rm -f "$IR_JSON"
                fi
              }
              trap cleanup EXIT

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
          program = "${self.packages.${system}.debug}/bin/network-solver-debug";
        };

        compile-and-solve = {
          type = "app";
          program = "${self.packages.${system}.compile-and-solve}/bin/compile-and-solve";
        };
      });
    };
}
