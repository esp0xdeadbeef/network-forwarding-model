{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/fabric/invariants/node-role-interface-degree.nix") { inherit lib self; }
