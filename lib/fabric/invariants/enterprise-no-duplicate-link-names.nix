{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/fabric/invariants/enterprise-no-duplicate-link-names.nix") { inherit lib self; }
