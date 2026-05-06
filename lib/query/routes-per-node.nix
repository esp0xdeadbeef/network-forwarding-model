{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/query/routes-per-node.nix") { inherit lib self; }
