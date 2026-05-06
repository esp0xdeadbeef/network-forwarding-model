{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/s88/Site/topology/overlay-reachability.nix") { inherit lib self; }
