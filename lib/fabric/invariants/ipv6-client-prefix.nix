{ lib }:

let
  common = import ./common.nix { inherit lib; };
  ip = import ../../net/ip-utils.nix { inherit lib; };
  network = import ../../model/network-utils.nix { inherit lib; };

  hasPrefixLength =
    cidr: want:
    let
      c = ip.splitCidr cidr;
    in
    c.prefix == want;

in
{
  check =
    { site }:
    let
      nodes = site.nodes or { };

      checks = lib.forEach (builtins.attrNames nodes) (
        name:
        let
          node = nodes.${name};
          role = node.role or null;
          nets = network.networksOfNode { } node;
        in
        if role != "access" then
          true
        else
          builtins.deepSeq (lib.forEach (builtins.attrNames nets) (
            netName:
            let
              net = nets.${netName};
            in
            if (net.kind or null) == "client" && (net.ipv6 or null) != null then
              common.assert_ (hasPrefixLength net.ipv6 64) ''
                invariants(ipv6-client-prefix):

                access client network must use /64 IPv6 prefix

                node: ${name}
                network: ${netName}
                configured: ${net.ipv6}
              ''
            else
              true
          )) true
      );
    in
    builtins.deepSeq checks true;
}
