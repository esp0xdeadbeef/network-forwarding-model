{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/fabric/invariants/no-duplicate-addrs.nix") { inherit lib self; }
