{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/s88/Unit/core/wan-links.nix") { inherit lib self; }
