# TODO — Missing Tenant Networks

## Problem

Solver output only contains tenant **admin**, while compiler input defines **mgmt**, **admin**, and **client**.
Result: mgmt/client networks and policies never appear in the solved topology.

## Evidence

Compiler output contains tenants:

* `domains.tenants = [mgmt, admin, client]`

But site attachments contain only:

* `sites[].attachment = tenants:admin`

## Hypothesis

The compiler collapses tenant attachments when building `sites[].attachment`, leaving only one entry.

## Tests

1. Check compiler attachments:

```
jq '.sites.esp0xdeadbeef["site-a"].attachment' output-compiler-signed.json
```

2. Check solver tenant owners:

```
jq '.sites.esp0xdeadbeef["site-a"].tenantPrefixOwners' output-solver-signed.json
```

## Expected

```
tenants:mgmt   → s-router-access-mgmt
tenants:admin  → s-router-access-admin
tenants:client → s-router-access-client
```

