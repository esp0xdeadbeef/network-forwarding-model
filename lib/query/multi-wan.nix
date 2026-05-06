{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/query/multi-wan.nix") { inherit lib self; }
