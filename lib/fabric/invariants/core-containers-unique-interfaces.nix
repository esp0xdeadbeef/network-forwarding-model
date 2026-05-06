{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/fabric/invariants/core-containers-unique-interfaces.nix") { inherit lib self; }
