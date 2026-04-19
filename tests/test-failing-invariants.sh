#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
system="${NIX_SYSTEM:-$(nix eval --impure --raw --expr 'builtins.currentSystem')}"

pass() {
  printf 'PASS %s\n' "$1"
}

fail() {
  printf 'FAIL %s\n' "$1" >&2
  if [ "${2-}" != "" ]; then
    printf '%s\n' "$2" >&2
  fi
  exit 1
}

build_expr() {
  local input_file="$1"
  cat <<EOF
let
  flake = builtins.getFlake "${repo_root}";
  input = import "${input_file}";
in
  flake.libBySystem."${system}".build { inherit input; }
EOF
}

write_negative_stable_link_id_input() {
  cat > "$1" <<'EOF'
{
  sites = {
    acme = {
      ams = {
        addressPools = {
          local = {
            ipv4 = "10.0.0.0/24";
          };

          p2p = {
            ipv4 = "10.0.1.0/24";
          };
        };

        attachments = [
          {
            unit = "access1";
            kind = "tenant";
            name = "tenant-a";
          }
        ];

        domains = {
          externals = [
            {
              kind = "external";
              name = "internet";
            }
          ];

          tenants = [
            {
              kind = "tenant";
              name = "tenant-a";
              ipv4 = "10.10.0.0/24";
            }
          ];
        };

        transit = {
          ordering = [
            "link::acme.ams::p2p-access1-policy1"
          ];
        };

        units = {
          access1 = {
            role = "access";
          };

          policy1 = {
            role = "policy";
          };

          core1 = {
            role = "core";
            uplinks = {
              internet = {
                addr4 = "198.51.100.2/31";
                peerAddr4 = "198.51.100.3";
                ipv4 = [ "203.0.113.0/24" ];
              };
            };
          };
        };
      };
    };
  };
}
EOF
}

write_negative_duplicate_loopback_input() {
  cat > "$1" <<'EOF'
{
  sites = {
    acme = {
      ams = {
        addressPools = {
          local = {
            ipv4 = "10.0.0.0/24";
          };

          p2p = {
            ipv4 = "10.0.1.0/24";
          };
        };

        attachments = [
          {
            unit = "access1";
            kind = "tenant";
            name = "tenant-a";
          }
        ];

        domains = {
          externals = [
            {
              kind = "external";
              name = "internet";
            }
          ];

          tenants = [
            {
              kind = "tenant";
              name = "tenant-a";
              ipv4 = "10.10.0.0/24";
            }
          ];
        };

        routerLoopbacks = {
          access1 = {
            ipv4 = "10.0.0.10";
          };

          policy1 = {
            ipv4 = "10.0.0.10";
          };
        };

        transit = {
          ordering = [
            [
              "access1"
              "policy1"
            ]
            [
              "policy1"
              "core1"
            ]
          ];
        };

        units = {
          access1 = {
            role = "access";
          };

          policy1 = {
            role = "policy";
          };

          core1 = {
            role = "core";
            uplinks = {
              internet = {
                addr4 = "198.51.100.2/31";
                peerAddr4 = "198.51.100.3";
                ipv4 = [ "203.0.113.0/24" ];
              };
            };
          };
        };
      };
    };
  };
}
EOF
}

write_negative_pool_overlap_input() {
  cat > "$1" <<'EOF'
{
  sites = {
    acme = {
      ams = {
        addressPools = {
          local = {
            ipv4 = "10.0.0.0/24";
          };

          p2p = {
            ipv4 = "10.10.0.0/24";
          };
        };

        attachments = [
          {
            unit = "access1";
            kind = "tenant";
            name = "tenant-a";
          }
        ];

        domains = {
          externals = [
            {
              kind = "external";
              name = "internet";
            }
          ];

          tenants = [
            {
              kind = "tenant";
              name = "tenant-a";
              ipv4 = "10.10.0.0/24";
            }
          ];
        };

        transit = {
          ordering = [
            [
              "access1"
              "policy1"
            ]
            [
              "policy1"
              "core1"
            ]
          ];
        };

        units = {
          access1 = {
            role = "access";
          };

          policy1 = {
            role = "policy";
          };

          core1 = {
            role = "core";
            uplinks = {
              internet = {
                addr4 = "198.51.100.2/31";
                peerAddr4 = "198.51.100.3";
                ipv4 = [ "203.0.113.0/24" ];
              };
            };
          };
        };
      };
    };
  };
}
EOF
}

write_negative_missing_role_input() {
  cat > "$1" <<'EOF'
{
  sites = {
    acme = {
      ams = {
        addressPools = {
          local = {
            ipv4 = "10.0.0.0/24";
          };

          p2p = {
            ipv4 = "10.0.1.0/24";
          };
        };

        attachments = [
          {
            unit = "access1";
            kind = "tenant";
            name = "tenant-a";
          }
        ];

        domains = {
          externals = [
            {
              kind = "external";
              name = "internet";
            }
          ];

          tenants = [
            {
              kind = "tenant";
              name = "tenant-a";
              ipv4 = "10.10.0.0/24";
            }
          ];
        };

        transit = {
          ordering = [
            [
              "access1"
              "policy1"
            ]
            [
              "policy1"
              "core1"
            ]
          ];
        };

        units = {
          access1 = {
            role = "access";
          };

          policy1 = { };

          core1 = {
            role = "core";
            uplinks = {
              internet = {
                addr4 = "198.51.100.2/31";
                peerAddr4 = "198.51.100.3";
                ipv4 = [ "203.0.113.0/24" ];
              };
            };
          };
        };
      };
    };
  };
}
EOF
}

expect_failure_any() {
  local name="$1"
  local input_file="$2"
  shift 2
  local expr
  local stderr

  expr="$(build_expr "$input_file")"

  if stderr="$({ nix eval --impure --show-trace --expr "$expr" >/dev/null; } 2>&1)"; then
    fail "$name" "expected evaluation failure"
  fi

  for needle in "$@"; do
    case "$stderr" in
      *"$needle"*)
        pass "$name"
        return 0
        ;;
    esac
  done

  fail "$name" "$stderr"
}

negative_stable_link_id_input="$tmpdir/negative-stable-link-id.nix"
negative_duplicate_loopback_input="$tmpdir/negative-duplicate-loopback.nix"
negative_pool_overlap_input="$tmpdir/negative-pool-overlap.nix"
negative_missing_role_input="$tmpdir/negative-missing-role.nix"

write_negative_stable_link_id_input "$negative_stable_link_id_input"
write_negative_duplicate_loopback_input "$negative_duplicate_loopback_input"
write_negative_pool_overlap_input "$negative_pool_overlap_input"
write_negative_missing_role_input "$negative_missing_role_input"

expect_failure_any \
  "stable-link-ids-are-output-only" \
  "$negative_stable_link_id_input" \
  "stable link identities are output-only" \
  "malformed transit.ordering entry"

expect_failure_any \
  "duplicate-explicit-loopbacks" \
  "$negative_duplicate_loopback_input" \
  "invariants(no-duplicate-addrs)" \
  "invariants(enterprise-no-duplicate-addrs)"

expect_failure_any \
  "p2p-pool-overlap" \
  "$negative_pool_overlap_input" \
  "overlapping prefixes are not allowed"

expect_failure_any \
  "missing-role-in-transit-ordering" \
  "$negative_missing_role_input" \
  "transit ordering references node without explicit role" \
  "missing required node role(s)"
