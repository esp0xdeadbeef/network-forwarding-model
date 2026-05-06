{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/model/prefix-utils.nix") { inherit lib self; }
