{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/net/cidr-normalize.nix") { inherit lib self; }
