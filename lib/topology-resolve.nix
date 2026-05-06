{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/topology-resolve.nix") { inherit lib self; }
