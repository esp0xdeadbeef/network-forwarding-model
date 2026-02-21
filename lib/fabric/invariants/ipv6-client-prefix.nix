{ lib }:

let
  assert_ = cond: msg: if cond then true else throw msg;

  splitCidr =
    cidr:
    let
      parts = lib.splitString "/" (toString cidr);
    in
    if builtins.length parts != 2 then
      throw "invariants(ipv6-client-prefix): invalid CIDR '${toString cidr}'"
    else
      {
        ip = builtins.elemAt parts 0;
        prefix = lib.toInt (builtins.elemAt parts 1);
      };

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
          let
            c = splitCidr nets.ipv6;
          in
          assert_ (c.prefix == 64) ''
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
