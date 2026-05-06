{ lib, self ? { outPath = ./.; }, ... }:

let
  ipv4 = import (self.outPath + "/implementation/lib/routing/cidr-summary/ipv4.nix") { inherit lib self; };
  ipv6 = import (self.outPath + "/implementation/lib/routing/cidr-summary/ipv6.nix") { inherit lib self; };

  summarizeCidrs =
    family: cidrs:
    if cidrs == [ ] then
      [ ]
    else if family == 4 then
      ipv4.summarize cidrs
    else
      ipv6.summarize cidrs;

in
{
  inherit summarizeCidrs;
}
