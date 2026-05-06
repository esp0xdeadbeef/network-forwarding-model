{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/p2p/link-specs.nix") { inherit lib self; }
