{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/s88/Site/topology/semantics.nix") { inherit lib self; }
