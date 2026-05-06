{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/s88/Site/topology/lane-access-uplinks.nix") { inherit lib self; }
