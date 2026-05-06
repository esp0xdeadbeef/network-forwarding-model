{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/query/node-context.nix") { inherit lib self; }
