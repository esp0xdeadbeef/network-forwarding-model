{ lib }:

let
  cidr = import ./cidr-utils.nix { inherit lib; };

  assert_ = cond: msg: if cond then true else throw msg;

  split =
    s:
    let
      parts = lib.splitString "/" (toString s);
    in
    if builtins.length parts != 2 then
      throw "invariants(p2p-link-prefix-lengths): invalid CIDR '${toString s}'"
    else
      {
        ip = builtins.elemAt parts 0;
        prefix = lib.toInt (builtins.elemAt parts 1);
      };

  checkEp =
    {
      siteName,
      linkName,
      nodeName,
      fam,
      addr,
      want,
    }:
    let
      c = split addr;
    in
    assert_ (c.prefix == want) ''
      invariants(p2p-link-prefix-lengths):

      invalid ${fam} prefix length on p2p endpoint

        site: ${siteName}
        link: ${linkName}
        node: ${nodeName}

        got:  ${toString addr}
        want: /${toString want}
    '';

in
{
  check =
    { site }:

    let
      siteName = toString (site.siteName or "<unknown-site>");
      links = site.links or null;

      checked =
        if links == null || !(builtins.isAttrs links) then
          true
        else
          let
            linkNames = builtins.attrNames links;

            results = lib.forEach linkNames (
              linkName:
              let
                l = links.${linkName};
              in
              if (l.kind or null) != "p2p" then
                true
              else
                let
                  eps = l.endpoints or { };
                  epNames = builtins.attrNames eps;

                  _members = assert_ (builtins.length epNames == 2) ''
                    invariants(p2p-link-prefix-lengths):

                    p2p link must have exactly 2 endpoints

                      site: ${siteName}
                      link: ${linkName}
                      endpoints: ${lib.concatStringsSep ", " epNames}
                  '';

                  checkOne =
                    nodeName:
                    let
                      ep = eps.${nodeName};

                      a4 = ep.addr4 or null;
                      a6 = ep.addr6 or null;

                      _a4 =
                        assert_ (a4 != null) ''
                          invariants(p2p-link-prefix-lengths):

                          missing addr4 on p2p endpoint

                            site: ${siteName}
                            link: ${linkName}
                            node: ${nodeName}
                        ''
                        && checkEp {
                          inherit siteName linkName nodeName;
                          fam = "IPv4";
                          addr = a4;
                          want = 31;
                        };

                      _a6 =
                        if a6 == null then
                          true
                        else
                          checkEp {
                            inherit siteName linkName nodeName;
                            fam = "IPv6";
                            addr = a6;
                            want = 127;
                          };
                    in
                    builtins.seq _a4 (builtins.seq _a6 true);

                  _both = lib.forEach epNames checkOne;
                in
                builtins.seq _members (builtins.deepSeq _both true)
            );
          in
          builtins.deepSeq results true;
    in
    builtins.deepSeq checked true;
}
