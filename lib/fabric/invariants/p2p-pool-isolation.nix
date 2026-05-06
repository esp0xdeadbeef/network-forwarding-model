{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/fabric/invariants/p2p-pool-isolation.nix") { inherit lib self; }
