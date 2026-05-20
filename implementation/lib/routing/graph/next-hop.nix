{ lib, self ? { outPath = ./.; }, ... }:

let
  ip = import (self.outPath + "/implementation/lib/net/ip-utils.nix") { inherit lib self; };
  link = import (self.outPath + "/implementation/lib/topology/link-utils.nix") { inherit lib self; };
  linkSearch = import ./link-search.nix { inherit lib self; };
in
{
  between =
    { links
    , from
    , to
    , stripMask ? ip.stripMask
    ,
    }:
    let
      lname = linkSearch.findLinkBetween { inherit links from to; };
      linkObj = if lname == null then null else links.${lname};
      epTo = if linkObj == null then { } else link.getEp lname linkObj to;
    in
    {
      linkName = lname;
      via4 = if epTo ? addr4 && epTo.addr4 != null then stripMask epTo.addr4 else null;
      via6 = if epTo ? addr6 && epTo.addr6 != null then stripMask epTo.addr6 else null;
    };
}
