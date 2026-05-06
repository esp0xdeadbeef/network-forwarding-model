{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/s88-support/default.nix") { inherit lib self; }
