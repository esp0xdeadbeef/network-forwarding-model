{
  description = "network-solver";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-network.url = "github:NixOS/nixpkgs/ac56c456ebe4901c561d3ebf1c98fbd970aea753";
    network-compiler.url = "github:esp0xdeadbeef/network-compiler";
    network-compiler.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nixpkgs-network, network-compiler }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems f;
      mkLib = system:
        let
          pkgs = import nixpkgs { inherit system; };
          patched = import nixpkgs-network { inherit system; };
        in
        import ./src/main.nix {
          lib = pkgs.lib // { network = patched.lib.network; };
        };
      mkPkgs = system: import nixpkgs { inherit system; };
    in
    {
      lib = forAll mkLib;

      packages = forAll (system:
        let
          pkgs = mkPkgs system;
        in
        {
          debug = pkgs.writeShellApplication {
            name = "network-solver-debug";
            runtimeInputs = [ pkgs.jq ];
            text = ''
              set -euo pipefail
              [ $# -ge 1 ] || { echo "usage: nix run ${self}#debug -- <ir.json>" >&2; exit 1; }
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
              [ $# -ge 1 ] || { echo "usage: nix run ${self}#compile-and-solve -- <compiler-inputs.nix>" >&2; exit 1; }
              INPUTS_NIX="$1"
              IR_JSON="$(mktemp)"
              trap 'rm -f "$IR_JSON"' EXIT

              nix run --no-warn-dirty ${network-compiler}#compile -- "$INPUTS_NIX" > "$IR_JSON"
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
