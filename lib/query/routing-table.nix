{ lib, routed }:

lib.mapAttrs (_: node: node.interfaces or { }) routed.nodes
