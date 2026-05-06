{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/lib/s88-support/attachments.nix") { inherit lib self; }
