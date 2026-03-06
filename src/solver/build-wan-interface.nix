{ uplink, linkName, nodeName, addr4, addr6, ll6 }:

let
  tenantSubject =
    if uplink ? ingressSubject && uplink.ingressSubject ? kind
       && uplink.ingressSubject.kind == "tenant"
    then uplink.ingressSubject.name
    else null;
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
  ra6Prefixes = [];
  routes4 = [];
  routes6 = [
    {
      dst = addr6;
      proto = "connected";
    }
    {
      dst = "::/0";
      proto = "uplink";
    }
  ];
  tenant = tenantSubject;
  type = "wan";
  uplink = uplink.name;
  upstream = uplink.name;
}
