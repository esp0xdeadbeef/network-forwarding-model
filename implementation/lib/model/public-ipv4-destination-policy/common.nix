{ lib, self ? { outPath = ./.; }, ... }:

let
  ip = import (self.outPath + "/implementation/lib/net/ip-utils.nix") { inherit lib self; };

  clean = value: if value == null then null else toString value;

  hasIPv4Shape = value:
    let
      parts = lib.splitString "." (ip.stripMask (toString value));
    in
    builtins.length parts == 4;

  pow2 = n: if n == 0 then 1 else 2 * pow2 (n - 1);

  ipv4Int = value: ip.ipv4ToInt (ip.parseIPv4 (ip.stripMask value));

  inRange = value: base: prefix:
    let
      n = ipv4Int value;
      b = ipv4Int base;
      size = 4294967296 / (pow2 prefix);
    in
    n >= b && n < b + size;

  isPublicIPv4 =
    value:
    let
      s = clean value;
    in
    s != null
    && hasIPv4Shape s
    && !(inRange s "10.0.0.0" 8)
    && !(inRange s "172.16.0.0" 12)
    && !(inRange s "192.168.0.0" 16)
    && !(inRange s "100.64.0.0" 10)
    && !(inRange s "127.0.0.0" 8)
    && !(inRange s "169.254.0.0" 16)
    && !(inRange s "0.0.0.0" 8)
    && !(inRange s "224.0.0.0" 4)
    && !(inRange s "240.0.0.0" 4);

  ipv4FieldNames = [
    "address"
    "addresses"
    "addr"
    "addr4"
    "ip"
    "ipv4"
    "publicAddress"
    "publicAddresses"
    "publicIp"
    "publicIp4"
    "publicIpv4"
    "publicIPv4"
  ];

  ipv4ValuesFrom =
    value:
    if value == null then
      [ ]
    else if builtins.isString value then
      lib.optional (hasIPv4Shape value) (toString value)
    else if builtins.isList value then
      lib.concatMap ipv4ValuesFrom value
    else if builtins.isAttrs value then
      lib.concatMap
        (name: if builtins.hasAttr name value then ipv4ValuesFrom value.${name} else [ ])
        ipv4FieldNames
    else
      [ ];

  mkRecord =
    { destinationClass
    , ownerKind
    , ownerName
    , address
    , source
    , serviceName ? null
    , publicIngress ? false
    }:
    let
      normalizedAddress = ip.stripMask address;
    in
    {
      id = "public-ipv4-destination::${toString normalizedAddress}";
      family = 4;
      address = normalizedAddress;
      inherit destinationClass ownerKind ownerName source serviceName publicIngress;
      genericWanInternet = false;
      modelOwned = true;
    };

  recordSet =
    records:
    builtins.listToAttrs (
      map (record: {
        name = record.id;
        value = record;
      }) records
    );

in
{
  inherit
    clean
    ipv4ValuesFrom
    isPublicIPv4
    mkRecord
    recordSet
    ;
}
