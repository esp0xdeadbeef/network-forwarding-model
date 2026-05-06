{ lib, self ? { outPath = ./.; }, ... }:
import ./common.nix { inherit lib self; }
