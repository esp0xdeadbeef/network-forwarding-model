{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/topology/link-utils.nix") { inherit lib self; }
