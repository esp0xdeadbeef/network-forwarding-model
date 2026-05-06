{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/s88/Enterprise/build.nix") { inherit lib self; }
