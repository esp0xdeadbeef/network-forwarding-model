{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/fabric/invariants/overlay-core-uplink-dedicated.nix") { inherit lib self; }
