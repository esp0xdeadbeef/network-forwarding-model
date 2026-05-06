{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/s88/Site/topology/overlay-name-set.nix") { inherit lib self; }
