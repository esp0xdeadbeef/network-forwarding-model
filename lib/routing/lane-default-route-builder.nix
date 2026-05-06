{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/routing/lane-default-route-builder.nix") { inherit lib self; }
