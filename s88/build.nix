{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/s88/build.nix") { inherit lib self; }
