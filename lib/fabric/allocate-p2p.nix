{ lib }:

site:

let
  addr = import ../model/addressing.nix { inherit lib; };

  sortedLinks = lib.sort (
    a: b:
    let
      ak = "${builtins.elemAt a 0}|${builtins.elemAt a 1}";
      bk = "${builtins.elemAt b 0}|${builtins.elemAt b 1}";
    in
    ak < bk
  ) site.links;

  mkLink =
    idx: pair:
    let
      a = builtins.elemAt pair 0;
      b = builtins.elemAt pair 1;

      hostA = idx * 2;
      hostB = hostA + 1;
    in
    {
      name = "p2p-${a}-${b}";
      value = {
        kind = "p2p";
        endpoints = {
          ${a} = {
            addr4 = addr.hostCidr hostA site.p2p-pool.ipv4;
            addr6 = addr.hostCidr hostA site.p2p-pool.ipv6;
          };
          ${b} = {
            addr4 = addr.hostCidr hostB site.p2p-pool.ipv4;
            addr6 = addr.hostCidr hostB site.p2p-pool.ipv6;
          };
        };
      };
    };

in
lib.listToAttrs (lib.imap0 mkLink sortedLinks)
