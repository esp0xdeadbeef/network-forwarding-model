{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/model/network-utils.nix") { inherit lib self; }
