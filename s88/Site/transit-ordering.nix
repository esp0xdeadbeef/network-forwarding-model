{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/s88/Site/transit-ordering.nix") { inherit lib self; }
