{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/p2p/alloc.nix") { inherit lib self; }
