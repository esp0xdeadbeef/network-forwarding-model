{ lib, self ? { outPath = ./.; }, ... }:
import ./attachments.nix { inherit lib self; }
