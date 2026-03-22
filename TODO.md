TODO — fix compiler transit adjacency contract
Goal

Restore the compiler output contract for site.transit.adjacencies so downstream consumers like network-control-plane-model can consume it without schema errors.

Problem

The compiler currently emits:

site.transit.adjacencies[].endpoints as an object
endpoint members in a link-style schema:
node
addr4
addr6
interface

Downstream expects:

site.transit.adjacencies[].endpoints as a 2-element list
endpoint members in a transit schema:
unit
local.ipv4
local.ipv6

This breaks CPM with:

site.transit.adjacencies[0].endpoints must be a list
Required fixes
1. Emit transit.adjacencies[].endpoints as a list, not an object

Current bad shape:

{
  "endpoints": {
    "s-router-access": { "...": "..." },
    "s-router-policy": { "...": "..." }
  }
}

Required shape:

{
  "endpoints": [
    {
      "unit": "s-router-access",
      "local": {
        "ipv4": "10.10.0.0",
        "ipv6": "fd42:dead:beef:1000:0:0:0:0"
      }
    },
    {
      "unit": "s-router-policy",
      "local": {
        "ipv4": "10.10.0.1",
        "ipv6": "fd42:dead:beef:1000:0:0:0:1"
      }
    }
  ]
}

Checklist:

 Replace object-style endpoints emission in site.transit.adjacencies
 Preserve deterministic ordering of the 2 endpoints
 Ensure every adjacency has exactly 2 endpoints
2. Convert endpoint members to transit schema

Current bad fields inside transit adjacency endpoints:

node
addr4
addr6
interface

Required fields:

unit
local.ipv4
local.ipv6

Checklist:

 Map node -> unit
 Strip prefix length from addr4 and store as local.ipv4
 Strip prefix length from addr6 and store as local.ipv6
 Do not emit interface inside transit.adjacencies[].endpoints
 Do not emit addr4 / addr6 inside transit.adjacencies[].endpoints
3. Keep links.* rich, but make transit.adjacencies canonical

links.* can stay renderer-friendly and verbose.

transit.adjacencies must stay consumer-friendly and stable.

Checklist:

 Keep site.links.*.endpoints unchanged if renderers need it
 Treat site.transit.adjacencies as a separate normalized contract
 Do not alias transit.adjacencies directly to links
4. Ensure transit adjacency metadata is preserved

Your newer shape added useful fields like:

link
members
kind
name

Those may be fine to keep, as long as the endpoint contract is fixed.

Checklist:

 Keep link if useful
 Keep members if useful
 Keep kind if useful
 Keep name only if it is deterministic and not redundant
 Do not let extra metadata change the endpoint contract
Invariants to enforce in compiler

For every site.transit.adjacencies[]:

 .endpoints | type == "array"
 .endpoints | length == 2
 every endpoint has .unit
 every endpoint has .local
 .local.ipv4 exists and contains no CIDR suffix
 .local.ipv6 exists and contains no CIDR suffix
 no endpoint contains addr4
 no endpoint contains addr6
 no endpoint contains node
 no endpoint contains interface
jq checks to add while fixing
Check 1: endpoints is always a list
./compile-one.sh | jq -e '
[
  .enterprise
  | to_entries[]
  | .value.site
  | to_entries[]
  | .value.transit.adjacencies[]
  | (.endpoints | type) == "array"
]
| all
'
Check 2: every adjacency has exactly 2 endpoints
./compile-one.sh | jq -e '
[
  .enterprise
  | to_entries[]
  | .value.site
  | to_entries[]
  | .value.transit.adjacencies[]
  | (.endpoints | length == 2)
]
| all
'
Check 3: every endpoint has the expected shape
./compile-one.sh | jq -e '
[
  .enterprise
  | to_entries[]
  | .value.site
  | to_entries[]
  | .value.transit.adjacencies[]
  | .endpoints[]
  | (
      has("unit")
      and has("local")
      and (.local | type == "object")
      and (.local | has("ipv4"))
      and (.local | has("ipv6"))
      and (has("node") | not)
      and (has("addr4") | not)
      and (has("addr6") | not)
      and (has("interface") | not)
    )
]
| all
'
Check 4: IPv4/IPv6 locals do not contain CIDR suffixes
./compile-one.sh | jq -e '
[
  .enterprise
  | to_entries[]
  | .value.site
  | to_entries[]
  | .value.transit.adjacencies[]
  | .endpoints[]
  | (
      (.local.ipv4 | contains("/") | not)
      and
      (.local.ipv6 | contains("/") | not)
    )
]
| all
'
Expected end state

After the fix:

 network-forwarding-model emits site.transit.adjacencies[].endpoints as a 2-element list
 each endpoint is { unit, local = { ipv4, ipv6 } }
 CPM no longer errors on site.transit.adjacencies[0].endpoints must be a list
 links remains rich for renderers
 transit.adjacencies remains canonical for downstream model consumers
