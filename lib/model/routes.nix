{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/model/routes.nix") { inherit lib self; }
