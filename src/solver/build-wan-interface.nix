{ uplink, linkName, nodeName, addr4, addr6, ll6 }:

let
  tenantSubject =
    if uplink ? ingressSubject && uplink.ingressSubject ? kind
       && uplink.ingressSubject.kind == "tenant"
       && uplink.ingressSubject ? name
       && uplink.ingressSubject.name != null
    then uplink.ingressSubject.name
    else "unclassified";
in
{
  acceptRA = false;
  addr4 = addr4;
  addr6 = addr6;
  addr6Public = null;
  carrier = "wan";
  dhcp = true;
  export = true;
  gateway = true;
  kind = "wan";
  link = linkName;
  ll6 = ll6;
  overlay = null;
  ra6Prefixes = [ ];
  routes = {
    ipv4 = [ ];
    ipv6 = [ ];
  };
  tenant = tenantSubject;
  type = "wan";
  uplink = uplink.name;
  upstream = uplink.name;
}
