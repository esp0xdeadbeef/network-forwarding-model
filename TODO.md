### TODO

* Align policy naming  
    Standardize on `policyIntent` (update documentation accordingly) to avoid mismatch with the README.
    
* Move query helpers to tooling  
    Keep the solver output as a pure topology graph. If inspection helpers are needed, place them under `tools/query/`.
    
* Keep solver output free of compiler artifacts  
    Ensure no compiler-stage metadata leaks into the solver graph (e.g. `compilerIR`, algorithm hints).
    
* Export uplink-learned routes from cores to the upstream-selector  
    Ensure prefixes learned via uplinks (e.g. routes with `proto: uplink`) are propagated from core nodes to the upstream-selector so upstream reachability is visible in its routing table.
