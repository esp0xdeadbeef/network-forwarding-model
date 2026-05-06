{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/s88/Site/topology/pools.nix") { inherit lib self; }
