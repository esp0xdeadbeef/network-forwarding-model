{ lib }:

let
  assert_ = cond: msg: if cond then true else throw msg;

  splitCidr =
    cidr:
    let
      parts = lib.splitString "/" (toString cidr);
    in
    if builtins.length parts != 2 then
      throw "invariants(p2p-ipv6-prefixlen-127): invalid CIDR '${toString cidr}'"
    else
      {
        ip = builtins.elemAt parts 0;
        prefix = lib.toInt (builtins.elemAt parts 1);
      };

  checkAddr6 =
    {
      siteName,
      linkName,
      nodeName,
      addr6,
    }:
    let
      c = splitCidr addr6;
    in
    assert_ (c.prefix == 127) ''
      invariants(p2p-ipv6-prefixlen-127):

      p2p IPv6 endpoints MUST be /127 (one subnet per p2p link)

        site: ${siteName}
        link: ${linkName}
        node: ${nodeName}

        got:  ${toString addr6}
        want: /127
    '';

  forEachEndpoint =
    {
      siteName,
      linkName,
      endpoints,
    }:
    let
      epNames = builtins.attrNames endpoints;
      _two = assert_ (builtins.length epNames == 2) ''
        invariants(p2p-ipv6-prefixlen-127):

        p2p link must have exactly 2 endpoints

          site: ${siteName}
          link: ${linkName}
          endpoints: ${lib.concatStringsSep ", " epNames}
      '';
      _ = lib.forEach epNames (
        n:
        let
          a6 = endpoints.${n}.addr6 or null;
        in
        if a6 == null then
          true
        else
          checkAddr6 {
            inherit siteName linkName;
            nodeName = n;
            addr6 = a6;
          }
      );
    in
    builtins.seq _two (builtins.deepSeq _ true);

  checkLinksBlock =
    { siteName, links }:
    lib.forEach (builtins.attrNames links) (
      linkName:
      let
        l = links.${linkName};
      in
      if (l.kind or null) != "p2p" then
        true
      else
        forEachEndpoint {
          inherit siteName linkName;
          endpoints = l.endpoints or { };
        }
    );

  checkNodeIfaces =
    { siteName, nodes }:
    let
      checkIface =
        nodeName: ifName: iface:
        if (iface.kind or null) != "p2p" then
          true
        else
          let
            a6 = iface.addr6 or null;
          in
          if a6 == null then
            true
          else
            checkAddr6 {
              inherit siteName;
              linkName = ifName;
              inherit nodeName;
              addr6 = a6;
            };

      walk =
        nodeName: v:
        if builtins.isAttrs v && v ? interfaces && builtins.isAttrs v.interfaces then
          lib.forEach (builtins.attrNames v.interfaces) (
            ifName: checkIface nodeName ifName v.interfaces.${ifName}
          )
        else
          true;

      isContainerAttr =
        name: v:
        builtins.isAttrs v
        && !(lib.elem name [
          "role"
          "networks"
          "interfaces"
        ]);

      containersOf = node: builtins.attrNames (lib.filterAttrs isContainerAttr node);

      checkNode =
        nodeName:
        let
          node = nodes.${nodeName};
          conts = containersOf node;
          _top = walk nodeName node;
          _conts = lib.forEach conts (cname: walk nodeName (node.${cname} or { }));
        in
        builtins.seq _top (builtins.deepSeq _conts true);

      _ = lib.forEach (builtins.attrNames nodes) checkNode;
    in
    builtins.deepSeq _ true;

in
{
  check =
    { site }:
    let
      siteName = toString (site.siteName or "<unknown-site>");
      links = site.links or null;
      nodes = site.nodes or { };

      _links =
        if links == null || !(builtins.isAttrs links) then
          true
        else
          builtins.deepSeq (checkLinksBlock { inherit siteName links; }) true;

      _nodes = builtins.deepSeq (checkNodeIfaces { inherit siteName nodes; }) true;
    in
    builtins.seq _links (builtins.seq _nodes true);
}
