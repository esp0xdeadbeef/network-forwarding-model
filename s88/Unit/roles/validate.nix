{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/s88/Unit/roles/validate.nix") { inherit lib self; }
