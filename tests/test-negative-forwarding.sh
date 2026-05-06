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

expect_failure() {
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

write_p2p_pool_exhausted_input() {
  cat > "$1" <<'EOF'
{
  sites.acme.ams = {
    addressPools = {
      local.ipv4 = "10.0.0.0/24";
      p2p.ipv4 = "10.0.1.0/31";
    };
    attachments = [ { unit = "access1"; kind = "tenant"; name = "tenant-a"; } ];
    domains = {
      externals = [ { kind = "external"; name = "internet"; } ];
      tenants = [ { kind = "tenant"; name = "tenant-a"; ipv4 = "10.10.0.0/24"; } ];
    };
    transit.ordering = [
      [ "access1" "policy1" ]
      [ "policy1" "core1" ]
    ];
    units = {
      access1.role = "access";
      policy1.role = "policy";
      core1 = {
        role = "core";
        uplinks.internet = {
          addr4 = "198.51.100.2/31";
          peerAddr4 = "198.51.100.3";
          ipv4 = [ "203.0.113.0/24" ];
        };
      };
    };
  };
}
EOF
}

write_incomplete_ipv4_uplink_input() {
  cat > "$1" <<'EOF'
{
  sites.acme.ams = {
    addressPools = {
      local.ipv4 = "10.0.0.0/24";
      p2p.ipv4 = "10.0.1.0/24";
    };
    attachments = [ { unit = "access1"; kind = "tenant"; name = "tenant-a"; } ];
    domains = {
      externals = [ { kind = "external"; name = "internet"; } ];
      tenants = [ { kind = "tenant"; name = "tenant-a"; ipv4 = "10.10.0.0/24"; } ];
    };
    transit.ordering = [
      [ "access1" "policy1" ]
      [ "policy1" "core1" ]
    ];
    units = {
      access1.role = "access";
      policy1.role = "policy";
      core1 = {
        role = "core";
        uplinks.internet = {
          addr4 = "198.51.100.2/31";
          ipv4 = [ "0.0.0.0/0" ];
        };
      };
    };
  };
}
EOF
}

write_incomplete_ipv6_uplink_input() {
  cat > "$1" <<'EOF'
{
  sites.acme.ams = {
    addressPools = {
      local.ipv4 = "10.0.0.0/24";
      p2p.ipv4 = "10.0.1.0/24";
    };
    attachments = [ { unit = "access1"; kind = "tenant"; name = "tenant-a"; } ];
    domains = {
      externals = [ { kind = "external"; name = "internet"; } ];
      tenants = [ { kind = "tenant"; name = "tenant-a"; ipv4 = "10.10.0.0/24"; } ];
    };
    transit.ordering = [
      [ "access1" "policy1" ]
      [ "policy1" "core1" ]
    ];
    units = {
      access1.role = "access";
      policy1.role = "policy";
      core1 = {
        role = "core";
        uplinks.internet = {
          addr4 = "198.51.100.2/31";
          peerAddr4 = "198.51.100.3";
          ipv4 = [ "0.0.0.0/0" ];
          addr6 = "2001:db8:1::2/127";
          ipv6 = [ "::/0" ];
        };
      };
    };
  };
}
EOF
}

write_duplicate_uplink_name_input() {
  cat > "$1" <<'EOF'
{
  sites.acme.ams = {
    addressPools = {
      local.ipv4 = "10.0.0.0/24";
      p2p.ipv4 = "10.0.1.0/24";
    };
    attachments = [ { unit = "access1"; kind = "tenant"; name = "tenant-a"; } ];
    domains = {
      externals = [ { kind = "external"; name = "internet"; } ];
      tenants = [ { kind = "tenant"; name = "tenant-a"; ipv4 = "10.10.0.0/24"; } ];
    };
    transit.ordering = [
      [ "access1" "policy1" ]
      [ "policy1" "upstream1" ]
      [ "upstream1" "coreA" ]
      [ "upstream1" "coreB" ]
    ];
    units = {
      access1.role = "access";
      policy1.role = "policy";
      upstream1.role = "upstream-selector";
      coreA = {
        role = "core";
        uplinks.internet = {
          addr4 = "198.51.100.2/31";
          peerAddr4 = "198.51.100.3";
          ipv4 = [ "0.0.0.0/0" ];
        };
      };
      coreB = {
        role = "core";
        uplinks.internet = {
          addr4 = "203.0.113.2/31";
          peerAddr4 = "203.0.113.3";
          ipv4 = [ "0.0.0.0/0" ];
        };
      };
    };
  };
}
EOF
}

p2p_pool_exhausted_input="$tmpdir/p2p-pool-exhausted.nix"
incomplete_ipv4_uplink_input="$tmpdir/incomplete-ipv4-uplink.nix"
incomplete_ipv6_uplink_input="$tmpdir/incomplete-ipv6-uplink.nix"
duplicate_uplink_name_input="$tmpdir/duplicate-uplink-name.nix"

write_p2p_pool_exhausted_input "$p2p_pool_exhausted_input"
write_incomplete_ipv4_uplink_input "$incomplete_ipv4_uplink_input"
write_incomplete_ipv6_uplink_input "$incomplete_ipv6_uplink_input"
write_duplicate_uplink_name_input "$duplicate_uplink_name_input"

expect_failure "p2p-pool-exhausted" "$p2p_pool_exhausted_input" \
  "pool capacity exhausted" \
  "p2p pool exhausted"

expect_failure "incomplete-ipv4-uplink" "$incomplete_ipv4_uplink_input" \
  "incomplete IPv4 WAN uplink endpoint"

expect_failure "incomplete-ipv6-uplink" "$incomplete_ipv6_uplink_input" \
  "incomplete IPv6 WAN uplink endpoint"

expect_failure "duplicate-uplink-name" "$duplicate_uplink_name_input" \
  "forwarding uplink names must be unique across cores"
