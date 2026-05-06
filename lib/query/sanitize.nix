{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/query/sanitize.nix") { inherit lib self; }
