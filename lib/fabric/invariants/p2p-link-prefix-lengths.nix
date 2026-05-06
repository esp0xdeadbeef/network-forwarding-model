{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/fabric/invariants/p2p-link-prefix-lengths.nix") { inherit lib self; }
