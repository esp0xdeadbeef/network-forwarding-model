{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/routing/overlay-core-selection.nix") { inherit lib self; }
