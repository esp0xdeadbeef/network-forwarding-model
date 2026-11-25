# shellcheck shell=bash
# Point <nixpkgs> at the pin this commit ships, not at whatever NIX_PATH holds.
#
# Six cases in this repository write `import <nixpkgs/lib>` inside a fixture and
# then evaluate it with `nix eval -f`. On a workstation that resolves through the
# ambient NIX_PATH (channels, or `nixpkgs=flake:nixpkgs` in the default), so the
# cases pass and the dependency is invisible. CI sets NIX_PATH to the empty string,
# and an empty NIX_PATH is not "unset": the default `nixpkgs=flake:nixpkgs` entry
# is only installed when the variable is absent, so every one of those fixtures
# died with
#
#   error: file 'nixpkgs/lib' was not found in the Nix search path
#
# Four matrix jobs were red for that and for nothing in the code under test
# (FS-260-HDS-010-SDS-010-SMS-050, FS-315-HDS-010-SDS-010-SMS-010,
# FS-940-HDS-010-SDS-020-SMS-030, FS-940-HDS-010-SDS-020-SMS-050). The same
# commit was green on the laptop that wrote it, which is exactly the failure mode
# a test must not have.
#
# The pin is read from the repository's own committed flake.lock through
# `builtins.getFlake`, the idiom the rest of the suite already uses
# (`flake.inputs.nixpkgs.lib` in lane-ownership-report.nix, the FS-315 generic
# lane case, ...). The inputs are already in the store because the flake gate
# evaluated this lock; no network fetch is implied.
#
# Usage, from a case that has repo_root:
#
#   source "${repo_root}/tests/lib/pinned-nixpkgs.sh"
#   pin_nixpkgs "${repo_root}"
#
# It exports NIX_PATH for the rest of the case and for the `nix` children it
# spawns. It deliberately does not prepend anything else: a case that needs more
# of NIX_PATH should ask for it by name.
pin_nixpkgs() {
  local repo_root="${1:?pin_nixpkgs: repository root required}"
  local pin
  pin="$(nix eval --raw --impure --expr \
    "(builtins.getFlake \"path:${repo_root}\").inputs.nixpkgs.outPath")" || {
    printf 'pinned-nixpkgs: cannot read the nixpkgs pin from %s/flake.lock\n' "${repo_root}" >&2
    return 1
  }
  export NIX_PATH="nixpkgs=${pin}"
}
