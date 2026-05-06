{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/s88/Unit/roles/input-role.nix") { inherit lib self; }
