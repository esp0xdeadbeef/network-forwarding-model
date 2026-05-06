{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/lib/collect-nix-files.nix") { inherit lib self; }
