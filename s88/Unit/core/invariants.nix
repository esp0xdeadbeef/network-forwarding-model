{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/s88/Unit/core/invariants.nix") { inherit lib self; }
