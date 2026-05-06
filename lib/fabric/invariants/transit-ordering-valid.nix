{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/fabric/invariants/transit-ordering-valid.nix") { inherit lib self; }
