{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/routing/cidr-summary.nix") { inherit lib self; }
