{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/query/wan.nix") { inherit lib self; }
