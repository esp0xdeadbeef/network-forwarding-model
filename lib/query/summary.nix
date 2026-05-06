{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/query/summary.nix") { inherit lib self; }
