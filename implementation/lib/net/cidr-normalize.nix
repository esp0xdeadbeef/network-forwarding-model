{ lib, self ? { outPath = ./.; }, ... }:

let
  ip = import ./ip-utils.nix { inherit lib self; };
  cidr = import (self.outPath + "/implementation/lib/fabric/invariants/cidr-utils.nix") { inherit lib self; };

  splitCidr = ip.splitCidr;
  intToV4 = ip.intToIPv4;

  canonicalCidr =
    cidrStr:
    let
      c = splitCidr cidrStr;
      r = cidr.cidrRange cidrStr;
      base = if r.family == 4 then intToV4 r.start else toString r.start;
    in
    "${base}/${toString c.prefix}";
in
{
  inherit canonicalCidr;
}
