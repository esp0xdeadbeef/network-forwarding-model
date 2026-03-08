# TODO.md — Restructure solver output hierarchy

Goal: Change solver output layout so enterprise and site are explicit hierarchical namespaces.

Target structure:

enterprise.<MAP OF ENTERPRISES>.site.<MAP OF SITES>

Example logical structure:

enterprise.<enterprise>.site.<site>.<...>

Do not hardcode enterprise or site names anywhere in the schema.

---

## 1. Replace `sites` root object

[ ] Remove the current root object:

    sites

[ ] Replace it with:

    enterprise

---

## 2. Enterprise map

[ ] Under `enterprise`, create a map keyed by enterprise ID.

Structure:

    enterprise.<enterprise>

Example logical structure:

    enterprise.esp0xdeadbeef

---

## 3. Site map

[ ] Under each enterprise, create a `site` map.

Structure:

    enterprise.<enterprise>.site

[ ] Each entry in this map represents a site.

Structure:

    enterprise.<enterprise>.site.<site>

Example logical structure:

    enterprise.esp0xdeadbeef.site.site-a

---

## 4. Move all site data under the new hierarchy

[ ] Move everything currently located at:

    sites.<enterprise>.<site>.*

to:

    enterprise.<enterprise>.site.<site>.*

This includes:

[ ] topology  
[ ] nodes  
[ ] links  
[ ] tenantPrefixOwners  
[ ] uplinkNames  
[ ] policy  
[ ] policyNodeName  
[ ] upstreamSelectorNodeName  
[ ] routerLoopbacks  
[ ] transit  
[ ] domains  
[ ] units  

---

## 5. Export policy intent

[ ] Copy `communicationContract` from provenance into:

    enterprise.<enterprise>.site.<site>.policyIntent

[ ] Copy these fields exactly:

    [ ] relations
    [ ] services
    [ ] trafficTypes

Renderer must read policy intent from this location.

---

## 6. Remove NAT block

[ ] Remove the NAT structure from solver output.

Delete:

    nat.mode
    nat.owner
    nat.ingress

Renderer will generate NAT rules.

---

## 7. Keep policy rules empty

[ ] Solver must not generate firewall rules.

Keep:

    enterprise.<enterprise>.site.<site>.policy.rules = []

Renderer will synthesize firewall rules.

---

## 8. Acceptance condition

Renderer must be able to operate using only:

    enterprise.<enterprise>.site.<site>.policyIntent
    enterprise.<enterprise>.site.<site>.tenantPrefixOwners
    enterprise.<enterprise>.site.<site>.uplinkNames
    enterprise.<enterprise>.site.<site>.policyNodeName
    enterprise.<enterprise>.site.<site>.nodes
    enterprise.<enterprise>.site.<site>.links

Renderer must not depend on:

    meta.provenance.originalInputs
