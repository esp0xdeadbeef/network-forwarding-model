{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/fabric/invariants/overlay-interfaces-realized.nix") { inherit lib self; }
