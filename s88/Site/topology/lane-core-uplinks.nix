{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/s88/Site/topology/lane-core-uplinks.nix") { inherit lib self; }
