{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/topology/resolve-helpers.nix") { inherit lib self; }
