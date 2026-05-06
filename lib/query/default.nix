{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/query/default.nix") { inherit lib self; }
