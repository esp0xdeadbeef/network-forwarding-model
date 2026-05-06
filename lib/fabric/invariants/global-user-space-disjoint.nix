{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/fabric/invariants/global-user-space-disjoint.nix") { inherit lib self; }
