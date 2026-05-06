{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/routing/external-ingress-uplink-defaults.nix") { inherit lib self; }
