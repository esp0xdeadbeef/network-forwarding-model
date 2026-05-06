{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/fabric/invariants/p2p-ipv6-prefixlen-127.nix") { inherit lib self; }
