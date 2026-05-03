{ lib }:

let
  normalizedPair =
    firstEndpoint: secondEndpoint:
    let
      firstName = toString firstEndpoint;
      secondName = toString secondEndpoint;
    in
    if firstName < secondName then
      {
        a = firstName;
        b = secondName;
      }
    else
      {
        a = secondName;
        b = firstName;
      };

  sanitize =
    value:
    let
      raw = toString value;
      chars = lib.stringToCharacters raw;
      allowed =
        char:
        (char >= "a" && char <= "z")
        || (char >= "A" && char <= "Z")
        || (char >= "0" && char <= "9")
        || char == "-"
        || char == "_";
      normalized = builtins.concatStringsSep "" (map (char: if allowed char then char else "-") chars);
    in
    if normalized == "" then "lane" else normalized;

  linkNameFor =
    normalized:
    let
      lane = normalized.lane or "default";
      laneHash = builtins.substring 0 10 (builtins.hashString "sha256" (toString lane));
      laneSlug = sanitize lane;
    in
    if lane == "default" then
      "p2p-${normalized.a}-${normalized.b}"
    else
      "p2p-${normalized.a}-${normalized.b}--lane-${laneSlug}-${laneHash}";

  normalizeLinkSpec =
    link:
    if builtins.isList link && builtins.length link == 2 then
      let
        pair = normalizedPair (builtins.elemAt link 0) (builtins.elemAt link 1);
      in
      pair
      // {
        lane = "default";
        linkName = linkNameFor (pair // { lane = "default"; });
      }
    else if builtins.isAttrs link then
      let
        firstEndpoint = link.a or null;
        secondEndpoint = link.b or null;
        _ =
          if firstEndpoint == null || secondEndpoint == null then
            throw "network-forwarding-model: p2p link spec requires a and b"
          else
            true;
        pair = normalizedPair firstEndpoint secondEndpoint;
        lane = if (link.lane or null) == null then "default" else toString link.lane;
        normalized = pair // { inherit lane; };
        explicitName = link.name or link.linkName or null;
        linkName =
          if explicitName != null && toString explicitName != "" then
            toString explicitName
          else
            linkNameFor normalized;
      in
      normalized // { inherit linkName; }
    else
      throw "network-forwarding-model: invalid p2p link spec (expected [a b] or { a, b, lane? })";
in
{
  validate =
    links:
    let
      specs = map normalizeLinkSpec links;

      step =
        acc: link:
        if link.a == link.b then
          throw ''
            network-forwarding-model: invalid self-link in p2p link specs

            node: ${link.a}
          ''
        else if acc.seen ? "${link.linkName}" then
          throw ''
            network-forwarding-model: duplicate p2p linkName in p2p link specs

            linkName: ${link.linkName}
          ''
        else
          {
            seen = acc.seen // {
              "${link.linkName}" = true;
            };
            specs = acc.specs ++ [ link ];
          };

      result = builtins.foldl' step {
        seen = { };
        specs = [ ];
      } specs;
    in
    lib.sort (left: right: left.linkName < right.linkName) result.specs;
}
