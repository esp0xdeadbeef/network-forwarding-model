{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/routing/lane-metadata.nix") { inherit lib self; }
