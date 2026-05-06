{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/fabric/invariants/final-topology-integrity.nix") { inherit lib self; }
