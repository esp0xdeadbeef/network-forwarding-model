{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/fabric/transit-role-stages.nix") { inherit lib self; }
