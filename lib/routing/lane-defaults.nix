{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/routing/lane-defaults.nix") { inherit lib self; }
