{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/routing/tenant-prefix-owners.nix") { inherit lib self; }
