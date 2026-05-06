{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/fabric/invariants/loopbacks-in-local-pool.nix") { inherit lib self; }
