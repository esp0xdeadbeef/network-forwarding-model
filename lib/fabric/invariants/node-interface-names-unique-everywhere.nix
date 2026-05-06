{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/fabric/invariants/node-interface-names-unique-everywhere.nix") { inherit lib self; }
