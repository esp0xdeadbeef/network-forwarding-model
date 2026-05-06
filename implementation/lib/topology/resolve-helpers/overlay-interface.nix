{ ... }:

{
  nameFor = overlayName: "overlay-${toString overlayName}";

  build =
    {
      nodeName,
      ifName,
      overlayName,
      overlay ? { },
      reachability ? null,
    }:
    let
      reach0 = if reachability != null && builtins.isAttrs reachability then reachability else { };
    in
    {
      name = ifName;
      node = nodeName;
      interface = ifName;
      logical = true;
      virtual = true;
      l2 = false;
      kind = overlay.kind or "overlay";
      type = "overlay";
      carrier = "logical";
      gateway = false;
      addr4 = null;
      peerAddr4 = null;
      addr6 = null;
      peerAddr6 = null;
      addr6Public = null;
      subnet4 = null;
      subnet6 = null;
      ll6 = null;
      uplink = null;
      upstream = null;
      overlay = overlayName;
      transport = (builtins.removeAttrs overlay [ "terminateOn" "terminatesOn" "terminatedOn" "unit" "node" "name" ]) // {
        peerSite = reach0.peerSite or null;
      };
      routes = { ipv4 = reach0.routes4 or [ ]; ipv6 = reach0.routes6 or [ ]; };
      ra6Prefixes = [ ];
      acceptRA = false;
      dhcp = false;
    };
}
