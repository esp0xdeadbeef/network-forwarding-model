{ lib, routed }:

lib.filterAttrs (_: l: (l.kind or null) == "wan") routed.links
