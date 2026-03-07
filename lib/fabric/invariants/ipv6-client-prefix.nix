{ lib }:

let
  common = import ./common.nix { inherit lib; };
  ip = import ../../net/ip-utils.nix { inherit lib; };

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

      checks = lib.all (
        name:
        let
          node = nodes.${name};
          role = node.role or null;
          nets = node.networks or null;
        in
        if role == "access" && nets != null && (nets.kind or null) == "client" && (nets ? ipv6) then
          common.assert_ (hasPrefixLength nets.ipv6 64) ''
            invariants(ipv6-client-prefix):

            access client network must use /64 IPv6 prefix

              node: ${name}
              configured: ${nets.ipv6}
          ''
        else
          true
      ) (builtins.attrNames nodes);
    in
    builtins.deepSeq checks true;
}
