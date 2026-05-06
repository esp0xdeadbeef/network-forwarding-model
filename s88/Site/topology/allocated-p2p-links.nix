{ lib, self ? { outPath = ./.; }, ... }:
import (self.outPath + "/implementation/s88/Site/topology/allocated-p2p-links.nix") { inherit lib self; }
