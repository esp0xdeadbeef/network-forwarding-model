{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/s88/Unit/roles/build.nix") { inherit lib self; }
