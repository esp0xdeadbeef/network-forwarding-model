{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/s88/Unit/core/uplink-specs.nix") { inherit lib self; }
