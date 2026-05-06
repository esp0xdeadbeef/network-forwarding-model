{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/model/addressing.nix") { inherit lib self; }
