{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/fabric/invariants/user-prefixes-disjoint.nix") { inherit lib self; }
