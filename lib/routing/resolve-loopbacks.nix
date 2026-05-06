{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/routing/resolve-loopbacks.nix") { inherit lib self; }
