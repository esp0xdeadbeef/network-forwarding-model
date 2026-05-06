{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/s88/ControlModule/enforcement/build.nix") { inherit lib self; }
