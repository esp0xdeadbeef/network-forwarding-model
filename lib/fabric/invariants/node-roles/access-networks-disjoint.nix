{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/fabric/invariants/node-roles/access-networks-disjoint.nix") { inherit lib self; }
