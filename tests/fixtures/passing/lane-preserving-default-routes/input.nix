{
  sites = {
    acme = {
      ams = {
        addressPools = {
          local = {
            ipv4 = "10.42.0.0/24";
            ipv6 = "fd42:42::/64";
          };
          p2p = {
            ipv4 = "10.42.1.0/24";
            ipv6 = "fd42:42:1::/64";
          };
        };

        attachments = [
          {
            kind = "tenant";
            name = "mgmt";
            unit = "mgmt";
          }
          {
            kind = "tenant";
            name = "client";
            unit = "client";
          }
          {
            kind = "tenant";
            name = "streaming";
            unit = "streaming";
          }
        ];

        domains = {
          tenants = [
            {
              kind = "tenant";
              name = "mgmt";
              ipv4 = "10.10.10.0/24";
              ipv6 = "fd42:10:10::/64";
            }
            {
              kind = "tenant";
              name = "client";
              ipv4 = "10.10.20.0/24";
              ipv6 = "fd42:10:20::/64";
            }
            {
              kind = "tenant";
              name = "streaming";
              ipv4 = "10.10.30.0/24";
              ipv6 = "fd42:10:30::/64";
            }
          ];
          externals = [
            {
              kind = "external";
              name = "wan";
            }
          ];
        };

        communicationContract = {
          allowedRelations = [
            {
              id = "allow-mgmt-to-wan";
              action = "allow";
              from = {
                kind = "tenant";
                name = "mgmt";
              };
              to = {
                kind = "external";
                uplinks = [ "wan" ];
              };
              trafficType = "any";
            }
            {
              id = "allow-client-to-wan";
              action = "allow";
              from = {
                kind = "tenant";
                name = "client";
              };
              to = {
                kind = "external";
                uplinks = [ "wan" ];
              };
              trafficType = "any";
            }
            {
              id = "allow-streaming-to-wan";
              action = "allow";
              from = {
                kind = "tenant";
                name = "streaming";
              };
              to = {
                kind = "external";
                uplinks = [ "wan" ];
              };
              trafficType = "any";
            }
          ];
          services = [ ];
          trafficTypes = [ ];
        };

        transit = {
          ordering = [
            [ "mgmt" "downstream" ]
            [ "client" "downstream" ]
            [ "streaming" "downstream" ]
            [ "downstream" "policy" ]
            [ "policy" "upstream" ]
            [ "upstream" "core" ]
          ];
        };

        upstreams = {
          cores = {
            core = [
              {
                name = "wan";
                addr4 = "192.0.2.2/31";
                peerAddr4 = "192.0.2.3";
                addr6 = "2001:db8:42::2/127";
                peerAddr6 = "2001:db8:42::3";
                ipv4 = [ "0.0.0.0/0" ];
                ipv6 = [ "::/0" ];
              }
            ];
          };
        };

        units = {
          mgmt = {
            role = "access";
          };
          client = {
            role = "access";
          };
          streaming = {
            role = "access";
          };
          downstream = {
            role = "downstream-selector";
          };
          policy = {
            role = "policy";
          };
          upstream = {
            role = "upstream-selector";
          };
          core = {
            role = "core";
          };
        };
      };
    };
  };
}
