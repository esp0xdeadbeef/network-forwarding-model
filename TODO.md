TODO — Forwarding Model Output Cleanup (Renderer Safe)

Remove the following unused fields from forwarding model output:

acceptRA
dhcp
ra6Prefixes
addr6Public



# TODO: pass through `communicationContract.interfaceTags`

## Problem

The upstream solver accepts lab input that contains:

```nix
communicationContract.interfaceTags = {
  tenant-mgmt = "mgmt";
  tenant-admin = "admin";
  tenant-client = "client";
  external-wan = "wan";
  service-site-dns = "site-dns";
};
```

But the generated solver output drops that field.

Observed result in solver output:

* `enterprise.<name>.site.<name>.communicationContract` exists
* `trafficTypes`, `services`, and `allowedRelations` are present
* `communicationContract.interfaceTags` is missing

That causes downstream failure in `network-control-plane-model`:

```text
communicationContract requires explicit communicationContract.interfaceTags
```

## Required behavior

When input includes:

```nix
communicationContract.interfaceTags = { ... };
```

the upstream solver must preserve it in the normalized / canonical / signed solver output at:

```nix
enterprise.<name>.site.<name>.communicationContract.interfaceTags
```

## Acceptance criteria

* [ ] `communicationContract.interfaceTags` survives canonicalization.
* [ ] `communicationContract.interfaceTags` survives normalization.
* [ ] `communicationContract.interfaceTags` survives signing / final solver JSON emission.
* [ ] No legacy `policy` path is reintroduced.
* [ ] Final solver output contains:

  ```json
  {
    "enterprise": {
      "<enterprise>": {
        "site": {
          "<site>": {
            "communicationContract": {
              "interfaceTags": { "...": "..." }
            }
          }
        }
      }
    }
  }
  ```

## Tests to add upstream

* [ ] Fixture with `communicationContract.interfaceTags`.
* [ ] Assertion that solver output contains `communicationContract.interfaceTags`.
* [ ] Assertion that values are unchanged.
* [ ] Regression test proving the field is not silently dropped.

## Likely fix area

Investigate the upstream canonicalization / transformation path that rewrites:

* `communicationContract.relations` -> `communicationContract.allowedRelations`
* site-level normalized output assembly
* final signed solver JSON emission

The bug is likely in one of these places:

* field whitelist during canonicalization
* explicit attrset reconstruction of `communicationContract`
* normalization code that copies only `trafficTypes`, `services`, and relations-derived data

## Minimal regression check

This should evaluate to `true` after the fix:

```bash
jq -e '
  .enterprise
  | to_entries[]
  | .value.site
  | to_entries[]
  | .value.communicationContract.interfaceTags
  | type == "object"
' output-solver-signed.json
```

## Definition of done

* [ ] Input contains `communicationContract.interfaceTags`
* [ ] Solver output also contains `communicationContract.interfaceTags`
* [ ] Downstream `network-control-plane-model` no longer fails on missing explicit interface tags for valid updated labs

