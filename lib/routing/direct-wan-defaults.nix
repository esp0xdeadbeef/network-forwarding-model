{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/routing/direct-wan-defaults.nix") { inherit lib self; }
