#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

input_nix="${tmpdir}/input.nix"
ir_json="${tmpdir}/ir.json"
stdout_json="${tmpdir}/stdout.json"
stderr_log="${tmpdir}/stderr.log"

cat >"${input_nix}" <<'EOF'
{
  sites.acme.ams = {
    addressPools = {
      local.ipv4 = "10.0.0.0/24";
      p2p.ipv4 = "10.0.1.0/24";
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
          name = "east-west";
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

    transit.ordering = [
      [
        "access1"
        "policy1"
      ]
      [
        "policy1"
        "core1"
      ]
    ];

    transport.overlays = [
      {
        name = "east-west";
        terminateOn = "core1";
      }
    ];

    units = {
      access1.role = "access";
      policy1.role = "policy";
      core1 = {
        role = "core";
        uplinks.east-west.ipv4 = [ "0.0.0.0/0" ];
      };
    };
  };
}
EOF

nix eval --json --impure --expr "import ${input_nix}" >"${ir_json}"
nix run "${repo_root}#debug" -- "${ir_json}" >"${stdout_json}" 2>"${stderr_log}"

needle="overlay 'east-west' terminates on core node(s) but has no access-specific uplink lane"

if ! grep -Fq "WARNING: network-forwarding-model: acme.ams: ${needle}" "${stderr_log}"; then
  echo "FAIL overlay-access-lane-warning: CLI warning missing" >&2
  cat "${stderr_log}" >&2
  exit 1
fi

if ! jq -e --arg needle "${needle}" '
  any(.meta.networkForwardingModel.warningMessages[]?; contains($needle))
' "${stdout_json}" >/dev/null; then
  echo "FAIL overlay-access-lane-warning: model warning missing" >&2
  cat "${stdout_json}" >&2
  exit 1
fi

echo "PASS overlay-access-lane-warning"
