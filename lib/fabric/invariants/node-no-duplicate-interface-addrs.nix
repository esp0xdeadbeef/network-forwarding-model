{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/fabric/invariants/node-no-duplicate-interface-addrs.nix") { inherit lib self; }
