{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/routing/uplink-learned-routes.nix") { inherit lib self; }
