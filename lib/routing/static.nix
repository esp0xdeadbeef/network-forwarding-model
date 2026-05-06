{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/routing/static.nix") { inherit lib self; }
