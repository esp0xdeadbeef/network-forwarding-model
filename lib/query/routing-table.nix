{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/query/routing-table.nix") { inherit lib self; }
