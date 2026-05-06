{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/fabric/invariants/core-uplinks-present.nix") { inherit lib self; }
