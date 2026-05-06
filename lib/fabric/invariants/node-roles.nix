{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/fabric/invariants/node-roles.nix") { inherit lib self; }
