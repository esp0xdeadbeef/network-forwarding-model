#!/usr/bin/env bash
set -euo pipefail

echo "Show all nodes"
./dev/debug.sh examples/single-site 'c: c.nodes'

echo "Show links"
./dev/debug.sh examples/single-site 'c: c.links'

echo "Show routing tables (derived)"
./dev/debug.sh examples/single-site \
'c: import ./lib/query/routes-per-node.nix { topo = c; }'

echo "Show one node (core)"
./dev/debug.sh examples/single-site 'c: c.nodes."s-router-core"'

echo "List node names"
./dev/debug.sh examples/single-site 'c: builtins.attrNames c.nodes'

echo "Show policy-core links"
./dev/debug.sh examples/single-site '
c:
  lib.filterAttrs
    (name: _: builtins.match "policy-core.*" name != null)
    c.links
'

echo "Show policy-core link endpoints"
./dev/debug.sh examples/single-site '
c:
  lib.mapAttrs (_: l: l.endpoints)
    (lib.filterAttrs
      (name: _: builtins.match "policy-core.*" name != null)
      c.links)
'

