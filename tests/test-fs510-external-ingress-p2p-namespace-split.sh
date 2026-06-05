#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-510-HDS-010-SDS-010-SMS-020
# GAMP-ID: FS-510-HDS-010-SDS-010-SMS-030
# GAMP-ID: FS-510-HDS-010-SDS-010-SMS-040
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"

"${repo_root}/tests/test-external-ingress-uplink-defaults.sh"
