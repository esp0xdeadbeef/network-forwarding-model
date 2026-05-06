{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/s88/Site/topology/overlays.nix") { inherit lib self; }
