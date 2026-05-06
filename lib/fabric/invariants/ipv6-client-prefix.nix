{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/fabric/invariants/ipv6-client-prefix.nix") { inherit lib self; }
