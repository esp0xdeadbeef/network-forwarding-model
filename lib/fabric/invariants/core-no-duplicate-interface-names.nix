{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/fabric/invariants/core-no-duplicate-interface-names.nix") { inherit lib self; }
