{
  meta = {
    networkForwardingModel = {
      name = "network-forwarding-model";
      schemaVersion = 9;
    };
  };

  enterprise = {
    acme = {
      site = {
        ams = {
          siteId = "ams";
          siteName = "acme.ams";

          addressPools = {
            local = {
              ipv4 = "10.255.0.0/29";
              ipv6 = "fd00:ff::/124";
            };
            p2p = {
              ipv4 = "169.254.10.0/29";
              ipv6 = "fd00:10::/124";
            };
          };

          attachments = [
            {
              kind = "tenant";
              name = "tenant-a";
              unit = "access1";
            }
          ];

          domains = {
            tenants = [
              {
                name = "tenant-a";
                ipv4 = "10.20.0.0/24";
                ipv6 = "fd00:20::/64";
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
            allowedRelations = [ ];
            services = [ ];
            trafficTypes = [ ];
          };

          policy = {
            interfaceTags = { };
          };

          transit = {
            ordering = [
              [
                "access1"
                "policy1"
              ]
              [
                "policy1"
                "upstream1"
              ]
              [
                "upstream1"
                "core1"
              ]
            ];
          };

          upstreams = {
            cores = {
              core1 = [
                {
                  name = "wan";
                  addr4 = "192.0.2.2/31";
                  peerAddr4 = "192.0.2.3/31";
                  addr6 = "2001:db8::2/127";
                  peerAddr6 = "2001:db8::3/127";
                  ipv4 = [ "0.0.0.0/0" ];
                  ipv6 = [ "::/0" ];
                }
              ];
            };
          };

          nodes = {
            access1 = {
              role = "access";
            };

            policy1 = {
              role = "policy";
            };

            upstream1 = {
              role = "upstream-selector";
            };

            core1 = {
              role = "core";
            };
          };
        };
      };
    };
  };
}
