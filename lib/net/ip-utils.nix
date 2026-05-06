{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/net/ip-utils.nix") { inherit lib self; }
