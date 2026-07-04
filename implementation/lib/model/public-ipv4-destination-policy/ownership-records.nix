{ lib, self ? { outPath = ./.; }, ... }:

let
  common = import ./common.nix { inherit lib self; };
  inherit (common) clean ipv4ValuesFrom isPublicIPv4 mkRecord;

  tenantRecordsForSource =
    source: tenants:
    lib.concatMap
      (
        tenant:
        let
          tenantName = clean (tenant.name or null);
          values =
            ipv4ValuesFrom (tenant.ipv4 or null)
            ++ ipv4ValuesFrom (tenant.publicIpv4 or null)
            ++ ipv4ValuesFrom (tenant.publicIPv4 or null)
            ++ ipv4ValuesFrom (tenant.routedPrefixes or [ ]);
        in
        map
          (address:
          mkRecord {
            destinationClass = "enterprise-client";
            ownerKind = "tenant";
            ownerName = tenantName;
            inherit address;
            inherit source;
          })
          (lib.filter isPublicIPv4 values)
      )
      tenants;

  recordIdentity =
    record:
    builtins.concatStringsSep "|" [
      (record.address or "")
      (record.destinationClass or "")
      (record.ownerKind or "")
      (record.ownerName or "")
    ];

  dropRecordsAlreadyOwned =
    existing: candidates:
    let
      existingIdentities = map recordIdentity existing;
    in
    lib.filter
      (record: !(builtins.elem (recordIdentity record) existingIdentities))
      candidates;

  tenantRecords =
    site:
    let
      domainTenantRecords =
        tenantRecordsForSource "domains.tenants" (site.domains.tenants or site.tenants or [ ]);
      ownershipPrefixRecords =
        tenantRecordsForSource "ownership.prefixes" (
          lib.filter
            (prefix: builtins.isAttrs prefix && (prefix.kind or null) == "tenant")
            ((site.ownership or { }).prefixes or [ ])
        );
    in
    domainTenantRecords ++ dropRecordsAlreadyOwned domainTenantRecords ownershipPrefixRecords;

  serviceRecords =
    site:
    lib.concatMap
      (
        service:
        let
          serviceName = clean (service.name or null);
          values =
            ipv4ValuesFrom service
            ++ ipv4ValuesFrom (service.publicIngress or null)
            ++ ipv4ValuesFrom (service.ingress or null);
          publicIngress = (service.publicIngress.enabled or service.publicIngress or false) != false;
        in
        map
          (address:
          mkRecord {
            destinationClass = if publicIngress then "public-ingress" else "tenant-service";
            ownerKind = "service";
            ownerName = serviceName;
            inherit address publicIngress serviceName;
            source = "communicationContract.services";
          })
          (lib.filter isPublicIPv4 values)
      )
      ((site.communicationContract or { }).services or site.services or [ ]);

  endpointRecords =
    site:
    lib.concatMap
      (
        endpoint:
        let
          endpointName = clean (endpoint.name or null);
          values = ipv4ValuesFrom endpoint;
          providerOwned = (endpoint.providerOwned or false) == true || (endpoint.kind or null) == "provider";
        in
        map
          (address:
          mkRecord {
            destinationClass = if providerOwned then "provider-owned" else "locally-owned-routed";
            ownerKind = endpoint.kind or "endpoint";
            ownerName = endpointName;
            inherit address;
            source = "ownership.endpoints";
          })
          (lib.filter isPublicIPv4 values)
      )
      ((site.ownership or { }).endpoints or [ ]);

  localRecords =
    topo:
    lib.concatMap
      (
        nodeName:
        let
          ifaces = (topo.nodes.${nodeName} or { }).interfaces or { };
        in
        lib.concatMap
          (
            ifName:
            let
              iface = ifaces.${ifName} or { };
              values = ipv4ValuesFrom iface;
              isProvider = (iface.providerOwned or false) == true || (iface.kind or null) == "wan";
            in
            map
              (address:
              mkRecord {
                destinationClass = if isProvider then "provider-owned" else "locally-owned-routed";
                ownerKind = "interface";
                ownerName = "${nodeName}.${ifName}";
                inherit address;
                source = "nodes.interfaces";
              })
              (lib.filter isPublicIPv4 values)
          )
          (builtins.attrNames ifaces)
      )
      (builtins.attrNames (topo.nodes or { }));

in
{
  build = topo: tenantRecords topo ++ serviceRecords topo ++ endpointRecords topo ++ localRecords topo;
}
