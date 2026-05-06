{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/s88/Site/topology/overlay-peer-sites.nix") { inherit lib self; }
