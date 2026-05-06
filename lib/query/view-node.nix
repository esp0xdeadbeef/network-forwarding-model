{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/query/view-node.nix") { inherit lib self; }
