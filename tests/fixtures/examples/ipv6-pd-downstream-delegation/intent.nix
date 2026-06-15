{
  esp0xdeadbeef = {
    site-a = {
      communicationContract = {
        interfaceTags = {
          external-wan = "wan";
          service-admin-web = "admin-web";
          service-jump-host = "jump-host";
          service-site-dns = "site-dns";
          tenant-admin = "admin";
          tenant-client-b = "client-b";
          tenant-client-a = "client-a";
          tenant-mgmt = "mgmt";
        };
        relations = [
          {
            action = "allow";
            from = {
              kind = "tenant-set";
              members = [
                "mgmt"
                "admin"
                "client-a"
                "client-b"
              ];
            };
            id = "allow-tenants-to-site-dns";
            priority = 5;
            to = {
              kind = "service";
              name = "site-dns";
            };
            trafficType = "dns";
          }
          {
            action = "allow";
            from = {
              kind = "tenant-set";
              members = [ "mgmt" ];
            };
            id = "allow-mgmt-internal";
            priority = 10;
            to = {
              kind = "tenant-set";
              members = [
                "mgmt"
                "admin"
                "client-a"
                "client-b"
              ];
            };
            trafficType = "any";
          }
          {
            action = "allow";
            from = {
              kind = "tenant-set";
              members = [
                "mgmt"
                "admin"
                "client-a"
                "client-b"
              ];
            };
            id = "allow-icmp-anywhere";
            priority = 20;
            to = "any";
            trafficType = "icmp";
          }
          {
            action = "deny";
            from = {
              kind = "tenant-set";
              members = [
                "mgmt"
                "admin"
                "client-a"
                "client-b"
              ];
            };
            id = "deny-web-to-wan";
            priority = 50;
            to = {
              kind = "external";
              name = "wan";
            };
            trafficType = "web";
          }
          {
            action = "allow";
            from = {
              kind = "tenant-set";
              members = [
                "mgmt"
                "admin"
                "client-a"
                "client-b"
              ];
            };
            id = "allow-tenants-to-wan";
            priority = 100;
            to = {
              kind = "external";
              name = "wan";
            };
            trafficType = "any";
          }
          {
            action = "allow";
            from = {
              kind = "external";
              name = "wan";
            };
            id = "allow-wan-to-jump-host";
            priority = 110;
            to = {
              kind = "service";
              name = "jump-host";
            };
            trafficType = "ssh";
          }
          {
            action = "allow";
            from = {
              kind = "external";
              name = "wan";
            };
            id = "allow-wan-to-mgmt-icmp";
            priority = 115;
            to = {
              kind = "tenant";
              name = "mgmt";
            };
            trafficType = "icmp";
          }
          {
            action = "allow";
            from = {
              kind = "external";
              name = "wan";
            };
            id = "allow-wan-to-admin-web";
            priority = 120;
            to = {
              kind = "service";
              name = "admin-web";
            };
            trafficType = "web";
          }
        ];
        services = [
          {
            name = "site-dns";
            providers = [ "s-sigma" ];
            trafficType = "dns";
          }
          {
            name = "jump-host";
            providers = [ "s-sigma" ];
            trafficType = "ssh";
          }
          {
            name = "admin-web";
            providers = [ "web01" ];
            trafficType = "web";
          }
        ];
        trafficTypes = [
          {
            match = [
              {
                family = "any";
                proto = "icmp";
              }
            ];
            name = "icmp";
          }
          {
            match = [
              {
                dports = [ 53 ];
                family = "any";
                proto = "udp";
              }
              {
                dports = [ 53 ];
                family = "any";
                proto = "tcp";
              }
            ];
            name = "dns";
          }
          {
            match = [
              {
                dports = [ 22 ];
                family = "any";
                proto = "tcp";
              }
            ];
            name = "ssh";
          }
          {
            match = [
              {
                dports = [
                  80
                  443
                ];
                family = "any";
                proto = "tcp";
              }
            ];
            name = "web";
          }
          {
            match = [
              {
                dports = [ 51820 ];
                family = "any";
                proto = "udp";
              }
            ];
            name = "wireguard";
          }
        ];
      };
      ownership = {
        endpoints = [
          {
            kind = "host";
            name = "s-sigma";
            tenant = "mgmt";
          }
          {
            kind = "host";
            name = "web01";
            tenant = "admin";
          }
        ];
        prefixes = [
          {
            ipv4 = "10.20.10.0/24";
            ipv6 = "fd42:dead:beef:10::/64";
            kind = "tenant";
            name = "mgmt";
          }
          {
            ipv4 = "10.20.15.0/24";
            ipv6 = "fd42:dead:beef:15::/64";
            kind = "tenant";
            name = "admin";
          }
          {
            ipv4 = "10.20.20.0/24";
            ipv6 = "fd42:dead:beef:20::/64";
            kind = "tenant";
            name = "client-a";
          }
          {
            ipv4 = "10.20.30.0/24";
            ipv6 = "fd42:dead:beef:30::/64";
            kind = "tenant";
            name = "client-b";
            routedPrefixes = [
              {
                allocation = "runtime";
                family = "ipv6";
                name = "client-b-downstream-public";
                delegatedPrefixLength = 48;
                perTenantPrefixLength = 52;
                slot = 1;
                sourceFile = "/run/s88-ipv6-pd/wan.prefix";
              }
            ];
          }
        ];
      };
      ipv6 = {
        pd = {
          delegatedPrefixLength = 48;
          perTenantPrefixLength = 64;
          uplink = "wan";
        };
        tenants = {
          admin.mode = "slaac";
          client-a.mode = "dhcpv6";
          client-b.mode = "slaac";
          mgmt = {
            mode = "static";
            prefixes = [ "2001:db8:10::/64" ];
          };
        };
      };
      pools = {
        loopback = {
          ipv4 = "10.19.0.0/24";
          ipv6 = "fd42:dead:beef:1900::/118";
        };
        p2p = {
          ipv4 = "10.10.0.0/24";
          ipv6 = "fd42:dead:beef:1000::/118";
        };
      };
      topology = {
        links = [
          [
            "s-router-core-wan"
            "s-router-upstream-selector"
          ]
          [
            "s-router-upstream-selector"
            "s-router-policy"
          ]
          [
            "s-router-policy"
            "s-router-downstream-selector"
          ]
          [
            "s-router-downstream-selector"
            "s-router-access-client-a"
          ]
          [
            "s-router-downstream-selector"
            "s-router-access-client-b"
          ]
          [
            "s-router-downstream-selector"
            "s-router-access-admin"
          ]
          [
            "s-router-downstream-selector"
            "s-router-access-mgmt"
          ]
        ];
        nodes = {
          s-router-access-admin = {
            attachments = [
              {
                kind = "tenant";
                name = "admin";
              }
            ];
            role = "access";
          };
          s-router-access-client-a = {
            attachments = [
              {
                kind = "tenant";
                name = "client-a";
              }
            ];
            role = "access";
          };
          s-router-access-client-b = {
            attachments = [
              {
                kind = "tenant";
                name = "client-b";
              }
            ];
            role = "access";
          };
          s-router-access-mgmt = {
            attachments = [
              {
                kind = "tenant";
                name = "mgmt";
              }
            ];
            role = "access";
          };
          s-router-core-wan = {
            role = "core";
            uplinks = {
              wan = {
                ipv4 = [ "0.0.0.0/0" ];
                ipv6 = [ "::/0" ];
              };
            };
          };
          s-router-downstream-selector = {
            role = "downstream-selector";
          };
          s-router-policy = {
            role = "policy";
          };
          s-router-upstream-selector = {
            role = "upstream-selector";
          };
        };
      };
    };
  };
}
