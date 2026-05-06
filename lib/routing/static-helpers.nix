{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/routing/static-helpers.nix") { inherit lib self; }
