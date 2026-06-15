{
  esp = {
    home = {
      communicationContract = {
        interfaceTags = {
          external-east-west = "east-west";
          external-isp-a = "isp-a";
          external-isp-b = "isp-b";
          service-dmz-nebula = "dmz-nebula";
          service-home-hostile-4444 = "home-hostile-4444";
          service-site-dns-mgmt = "site-dns-mgmt";
          service-cast-control = "cast-control";
          service-cast-discovery = "cast-discovery";
          tenant-admin = "admin";
          tenant-client = "client";
          tenant-dmz = "dmz";
          tenant-hostile = "hostile";
          tenant-mgmt = "mgmt";
          tenant-streaming = "streaming";
        };
        relations = [
          {
            action = "allow";
            from = {
              kind = "external";
              uplinks = [
                "isp-a"
                "isp-b"
              ];
            };
            id = "allow-site-wan-icmp-anywhere";
            priority = 6;
            to = "any";
            trafficType = "icmp";
          }
          {
            action = "allow";
            from = {
              kind = "external";
              name = "east-west";
            };
            id = "allow-site-overlay-icmp-anywhere";
            priority = 7;
            to = "any";
            trafficType = "icmp";
          }
          {
            action = "allow";
            from = {
              kind = "tenant-set";
              members = [ "admin" ];
            };
            id = "allow-admin-to-mgmt";
            priority = 10;
            to = {
              kind = "tenant-set";
              members = [ "mgmt" ];
            };
            trafficType = "any";
          }
          {
            action = "deny";
            from = {
              kind = "tenant-set";
              members = [
                "client"
                "streaming"
                "dmz"
                "hostile"
              ];
            };
            id = "deny-production-to-mgmt";
            priority = 11;
            to = {
              kind = "tenant-set";
              members = [ "mgmt" ];
            };
            trafficType = "any";
          }
          {
            action = "deny";
            from = {
              kind = "tenant-set";
              members = [ "streaming" ];
            };
            id = "deny-streaming-to-client";
            priority = 12;
            to = {
              kind = "tenant-set";
              members = [ "client" ];
            };
            trafficType = "any";
          }
          {
            action = "deny";
            from = {
              kind = "tenant-set";
              members = [ "hostile" ];
            };
            id = "deny-hostile-to-local-tenants";
            priority = 13;
            to = {
              kind = "tenant-set";
              members = [
                "admin"
                "client"
                "streaming"
                "dmz"
              ];
            };
            trafficType = "any";
          }
          {
            action = "allow";
            from = {
              kind = "tenant-set";
              members = [
                "admin"
                "client"
                "streaming"
                "dmz"
              ];
            };
            id = "allow-tenants-to-site-dns";
            priority = 20;
            to = {
              kind = "service";
              name = "site-dns-mgmt";
            };
            trafficType = "dns";
          }
          {
            action = "allow";
            from = {
              kind = "service";
              name = "site-dns-mgmt";
            };
            id = "allow-site-dns-service-to-uplinks";
            priority = 24;
            to = {
              kind = "external";
              uplinks = [
                "isp-a"
                "isp-b"
              ];
            };
            trafficType = "dns";
          }
          {
            action = "deny";
            from = {
              kind = "tenant-set";
              members = [
                "admin"
                "client"
                "streaming"
                "dmz"
              ];
            };
            id = "deny-tenant-dns-to-uplinks";
            priority = 25;
            to = {
              kind = "external";
              uplinks = [
                "isp-a"
                "isp-b"
              ];
            };
            trafficType = "dns";
          }
          {
            action = "deny";
            from = {
              kind = "tenant-set";
              members = [ "hostile" ];
            };
            id = "deny-hostile-to-local-uplinks";
            priority = 26;
            to = {
              kind = "external";
              uplinks = [
                "isp-a"
                "isp-b"
              ];
            };
            trafficType = "any";
          }
          {
            action = "allow";
            from = {
              kind = "tenant-set";
              members = [ "client" ];
            };
            id = "allow-client-to-cast-discovery";
            priority = 30;
            to = {
              kind = "service";
              name = "cast-discovery";
            };
            trafficType = "cast-discovery";
          }
          {
            action = "allow";
            from = {
              kind = "tenant-set";
              members = [ "client" ];
            };
            id = "allow-client-to-cast-control";
            priority = 31;
            to = {
              kind = "service";
              name = "cast-control";
            };
            trafficType = "cast-control";
          }
          {
            action = "allow";
            from = {
              kind = "tenant-set";
              members = [ "hostile" ];
            };
            id = "allow-hostile-egress-to-edge-overlay";
            priority = 32;
            to = {
              kind = "external";
              name = "east-west";
            };
            trafficType = "any";
          }
          {
            action = "allow";
            from = {
              kind = "tenant-set";
              members = [
                "admin"
                "client"
                "streaming"
              ];
            };
            id = "allow-user-tenants-to-uplinks";
            priority = 100;
            to = {
              kind = "external";
              uplinks = [
                "isp-a"
                "isp-b"
              ];
            };
            trafficType = "any";
          }
          {
            action = "allow";
            from = {
              kind = "external";
              name = "east-west";
            };
            id = "allow-edge-public-4444-to-home-hostile";
            priority = 121;
            to = {
              kind = "service";
              name = "home-hostile-4444";
            };
            trafficType = "tcp-udp-4444";
          }
          {
            action = "allow";
            from = {
              kind = "tenant-set";
              members = [ "dmz" ];
            };
            id = "allow-dmz-to-uplinks";
            priority = 101;
            to = {
              kind = "external";
              uplinks = [
                "isp-a"
                "isp-b"
              ];
            };
            trafficType = "any";
          }
          {
            action = "allow";
            from = {
              kind = "external";
              name = "east-west";
            };
            id = "allow-east-west-to-site-dns";
            priority = 115;
            to = {
              kind = "service";
              name = "site-dns-mgmt";
            };
            trafficType = "dns";
          }
          {
            action = "allow";
            from = {
              kind = "external";
              uplinks = [
                "isp-a"
                "isp-b"
              ];
            };
            id = "allow-wan-to-dmz-nebula";
            priority = 120;
            to = {
              kind = "service";
              name = "dmz-nebula";
            };
            trafficType = "nebula";
          }
          {
            action = "allow";
            from = {
              kind = "external";
              name = "east-west";
            };
            id = "allow-nebula-underlay-to-uplinks";
            priority = 130;
            to = {
              kind = "external";
              uplinks = [
                "isp-a"
                "isp-b"
              ];
            };
            trafficType = "nebula";
          }
          {
            action = "allow";
            from = {
              kind = "external";
              name = "east-west";
            };
            id = "allow-nebula-runtime-underlay-to-uplinks";
            priority = 131;
            to = {
              kind = "external";
              uplinks = [
                "isp-a"
                "isp-b"
              ];
            };
            trafficType = "nebula-runtime";
          }
        ];
        services = [
          {
            name = "site-dns-mgmt";
            providers = [ "site-dns-mgmt" ];
            trafficType = "dns";
          }
          {
            name = "dmz-nebula";
            providers = [ "nebula01" ];
            trafficType = "nebula";
          }
          {
            name = "home-hostile-4444";
            providers = [ "home-hostile01" ];
            trafficType = "tcp-udp-4444";
          }
          {
            name = "cast-control";
            providers = [ "streaming01" ];
            trafficType = "cast-control";
          }
          {
            name = "cast-discovery";
            providers = [ "streaming01" ];
            trafficType = "cast-discovery";
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
                dports = [ 4444 ];
                family = "any";
                proto = "tcp";
              }
              {
                dports = [ 4444 ];
                family = "any";
                proto = "udp";
              }
            ];
            name = "tcp-udp-4444";
          }
          {
            match = [
              {
                dports = [ 4242 ];
                family = "any";
                proto = "udp";
              }
              {
                dports = [ 4242 ];
                family = "any";
                proto = "tcp";
              }
            ];
            name = "nebula";
          }
          {
            match = [
              {
                dports = [ 4243 ];
                family = "any";
                proto = "udp";
              }
            ];
            name = "nebula-runtime";
          }
          {
            match = [
              {
                dports = [
                  8008
                  8009
                ];
                family = "any";
                proto = "tcp";
              }
            ];
            name = "cast-control";
          }
          {
            match = [
              {
                dports = [ 5353 ];
                family = "any";
                proto = "udp";
              }
              {
                dports = [ 1900 ];
                family = "any";
                proto = "udp";
              }
            ];
            name = "cast-discovery";
          }
        ];
      };
      ownership = {
        endpoints = [
          {
            kind = "host";
            name = "nebula01";
            tenant = "dmz";
          }
          {
            kind = "host";
            name = "home-hostile01";
            tenant = "hostile";
          }
          {
            kind = "host";
            name = "site-dns-mgmt";
            tenant = "mgmt";
          }
          {
            kind = "host";
            name = "streaming01";
            tenant = "streaming";
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
            name = "client";
          }
          {
            ipv4 = "10.20.30.0/24";
            ipv6 = "fd42:dead:beef:30::/64";
            kind = "tenant";
            name = "dmz";
          }
          {
            ipv4 = "10.20.50.0/24";
            ipv6 = "fd42:dead:beef:50::/64";
            kind = "tenant";
            name = "streaming";
          }
          {
            ipv4 = "10.20.70.0/24";
            ipv6 = "fd42:dead:beef:70::/64";
            kind = "tenant";
            name = "hostile";
            routedPrefixes = [
              {
                allocation = "runtime";
                family = "ipv6";
                name = "home-hostile-public";
                prefixPostfix = "4444";
                delegatedPrefixLength = 64;
                perTenantPrefixLength = 64;
                slot = 0;
                sourceFile = "/run/secrets/access-node-ipv6-prefix-esp-home-example-router-access-hostile";
              }
            ];
          }
        ];
      };
      pools = {
        overlay = {
          ipv4 = {
            offsetStart = 10;
            perNodePrefixLength = 32;
            prefix = "100.96.10.0/24";
          };
          ipv6 = {
            offsetStart = 10;
            perNodePrefixLength = 128;
            prefix = "fd42:dead:beef:ee::/64";
          };
        };
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
            "home-example-router-core-isp-a"
            "home-example-router-upstream"
          ]
          [
            "home-example-router-core-isp-b"
            "home-example-router-upstream"
          ]
          [
            "home-example-router-core-nebula"
            "home-example-router-upstream"
          ]
          [
            "home-example-router-upstream"
            "home-example-router-policy"
          ]
          [
            "home-example-router-policy"
            "home-example-router-downstream"
          ]
          [
            "home-example-router-downstream"
            "home-example-router-access-admin"
          ]
          [
            "home-example-router-downstream"
            "home-example-router-access-client"
          ]
          [
            "home-example-router-downstream"
            "home-example-router-access-dmz"
          ]
          [
            "home-example-router-downstream"
            "home-example-router-access-hostile"
          ]
          [
            "home-example-router-downstream"
            "home-example-router-access-mgmt"
          ]
          [
            "home-example-router-downstream"
            "home-example-router-access-streaming"
          ]
        ];
        nodes = {
          home-example-router-access-admin = {
            attachments = [
              {
                kind = "tenant";
                name = "admin";
              }
            ];
            role = "access";
          };
          home-example-router-access-client = {
            attachments = [
              {
                kind = "tenant";
                name = "client";
              }
            ];
            role = "access";
          };
          home-example-router-access-dmz = {
            attachments = [
              {
                kind = "tenant";
                name = "dmz";
              }
            ];
            role = "access";
          };
          home-example-router-access-mgmt = {
            attachments = [
              {
                kind = "tenant";
                name = "mgmt";
              }
            ];
            role = "access";
          };
          home-example-router-access-hostile = {
            attachments = [
              {
                kind = "tenant";
                name = "hostile";
              }
            ];
            role = "access";
          };
          home-example-router-access-streaming = {
            attachments = [
              {
                kind = "tenant";
                name = "streaming";
              }
            ];
            role = "access";
          };
          home-example-router-core-isp-a = {
            role = "core";
            uplinks = {
              isp-a = {
                ipv4 = [ "0.0.0.0/0" ];
                ipv6 = [ "::/0" ];
              };
            };
          };
          home-example-router-core-isp-b = {
            role = "core";
            uplinks = {
              isp-b = {
                ipv4 = [ "0.0.0.0/0" ];
                ipv6 = [ "::/0" ];
              };
            };
          };
          home-example-router-core-nebula = {
            attachments = [
              {
                kind = "tenant";
                name = "client";
              }
            ];
            role = "core";
            uplinks = {
              east-west = {
                ipv4 = [
                  "10.50.10.0/24"
                  "10.50.15.0/24"
                  "10.50.20.0/24"
                  "10.50.30.0/24"
                  "10.50.50.0/24"
                  "10.70.10.0/24"
                  "10.90.10.0/24"
                  "0.0.0.0/0"
                ];
                ipv6 = [
                  "fd42:dead:feed:10::/64"
                  "fd42:dead:feed:15::/64"
                  "fd42:dead:feed:20::/64"
                  "fd42:dead:feed:30::/64"
                  "fd42:dead:feed:50::/64"
                  "fd42:dead:feed:70::/64"
                  "fd42:dead:cafe:10::/64"
                  "::/0"
                ];
              };
            };
          };
          home-example-router-downstream = {
            role = "downstream-selector";
          };
          home-example-router-policy = {
            role = "policy";
          };
          home-example-router-upstream = {
            role = "upstream-selector";
          };
        };
      };
      transport = {
        overlays = [
          {
            mustTraverse = [ "policy" ];
            name = "east-west";
            peerSites = [
              "esp.lab"
              "esp.edge"
            ];
            terminateOn = "home-example-router-core-nebula";
            underlayAccess = {
              kind = "tenant";
              name = "client";
            };
          }
        ];
      };
    };
    edge = {
      communicationContract = {
        interfaceTags = {
          external-east-west = "east-west";
          external-wan = "wan";
          service-lab-client-4445 = "lab-client-4445";
          service-dmz-nebula = "dmz-nebula";
          service-edge-dns-dmz = "edge-dns-dmz";
          service-edge-client-4446 = "edge-client-4446";
          service-home-hostile-4444 = "home-hostile-4444";
          tenant-client = "client";
          tenant-dmz = "dmz";
        };
        relations = [
          {
            action = "allow";
            from = {
              kind = "external";
              uplinks = [ "wan" ];
            };
            id = "allow-edge-wan-icmp-anywhere";
            priority = 6;
            to = "any";
            trafficType = "icmp";
          }
          {
            action = "allow";
            from = {
              kind = "external";
              name = "east-west";
            };
            id = "allow-edge-overlay-icmp-anywhere";
            priority = 7;
            to = "any";
            trafficType = "icmp";
          }
          {
            action = "allow";
            from = {
              kind = "tenant-set";
              members = [ "client" ];
            };
            id = "allow-edge-client-to-dmz-dns";
            priority = 20;
            to = {
              kind = "service";
              name = "edge-dns-dmz";
            };
            trafficType = "dns";
          }
          {
            action = "deny";
            from = {
              kind = "tenant-set";
              members = [ "client" ];
            };
            id = "deny-edge-client-dns-to-wan";
            priority = 25;
            to = {
              kind = "external";
              name = "wan";
            };
            trafficType = "dns";
          }
          {
            action = "allow";
            from = {
              kind = "tenant-set";
              members = [ "client" ];
            };
            id = "allow-edge-client-to-wan";
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
              kind = "tenant-set";
              members = [ "dmz" ];
            };
            id = "allow-edge-dmz-to-wan";
            priority = 101;
            to = {
              kind = "external";
              name = "wan";
            };
            trafficType = "any";
          }
          {
            action = "allow";
            from = {
              kind = "service";
              name = "edge-dns-dmz";
            };
            id = "allow-edge-dns-service-to-east-west";
            priority = 109;
            to = {
              kind = "external";
              name = "east-west";
            };
            trafficType = "dns";
          }
          {
            action = "allow";
            from = {
              kind = "service";
              name = "edge-dns-dmz";
            };
            id = "allow-edge-dns-service-to-wan";
            priority = 110;
            to = {
              kind = "external";
              name = "wan";
            };
            trafficType = "dns";
          }
          {
            action = "allow";
            from = {
              kind = "external";
              name = "east-west";
            };
            id = "allow-hostile-overlay-egress-to-wan";
            priority = 120;
            to = {
              kind = "external";
              uplinks = [ "wan" ];
            };
            trafficType = "any";
          }
          {
            action = "allow";
            from = {
              kind = "external";
              uplinks = [ "wan" ];
            };
            id = "allow-wan-to-dmz-nebula";
            priority = 125;
            to = {
              kind = "service";
              name = "dmz-nebula";
            };
            trafficType = "nebula";
          }
          {
            action = "allow";
            from = {
              kind = "external";
              name = "east-west";
            };
            id = "allow-east-west-underlay-to-dmz-nebula";
            priority = 126;
            to = {
              kind = "service";
              name = "dmz-nebula";
            };
            trafficType = "nebula";
          }
          {
            action = "allow";
            from = {
              kind = "external";
              uplinks = [ "wan" ];
            };
            id = "allow-wan-to-home-hostile-4444";
            priority = 130;
            to = {
              kind = "service";
              name = "home-hostile-4444";
            };
            trafficType = "tcp-udp-4444";
          }
          {
            action = "allow";
            from = {
              kind = "external";
              uplinks = [ "wan" ];
            };
            id = "allow-wan-to-lab-client-4445";
            priority = 131;
            to = {
              kind = "service";
              name = "lab-client-4445";
            };
            trafficType = "tcp-udp-4445";
          }
          {
            action = "allow";
            from = {
              kind = "external";
              uplinks = [ "wan" ];
            };
            id = "allow-wan-to-edge-client-4446";
            priority = 132;
            to = {
              kind = "service";
              name = "edge-client-4446";
            };
            trafficType = "tcp-udp-4446";
          }
          {
            action = "allow";
            from = {
              kind = "external";
              name = "east-west";
            };
            id = "allow-overlay-to-hostile-public-dns";
            priority = 133;
            to = {
              kind = "service";
              name = "hostile-public-dns";
            };
            trafficType = "dns";
          }
        ];
        services = [
          {
            name = "edge-dns-dmz";
            providers = [ "edge-dns-dmz" ];
            trafficType = "dns";
          }
          {
            name = "dmz-nebula";
            providers = [ "edge-example-router-lighthouse" ];
            trafficType = "nebula";
          }
          {
            name = "home-hostile-4444";
            providers = [ "home-hostile01" ];
            trafficType = "tcp-udp-4444";
          }
          {
            name = "lab-client-4445";
            providers = [ "lab-client01" ];
            trafficType = "tcp-udp-4445";
          }
          {
            name = "edge-client-4446";
            providers = [ "edge-client01" ];
            trafficType = "tcp-udp-4446";
          }
          {
            name = "hostile-public-dns";
            providers = [ "edge-dns-dmz" ];
            trafficType = "dns";
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
                dports = [ 4242 ];
                family = "any";
                proto = "udp";
              }
              {
                dports = [ 4242 ];
                family = "any";
                proto = "tcp";
              }
            ];
            name = "nebula";
          }
          {
            match = [
              {
                dports = [ 4444 ];
                family = "any";
                proto = "tcp";
              }
              {
                dports = [ 4444 ];
                family = "any";
                proto = "udp";
              }
            ];
            name = "tcp-udp-4444";
          }
          {
            match = [
              {
                dports = [ 4445 ];
                family = "any";
                proto = "tcp";
              }
              {
                dports = [ 4445 ];
                family = "any";
                proto = "udp";
              }
            ];
            name = "tcp-udp-4445";
          }
          {
            match = [
              {
                dports = [ 4446 ];
                family = "any";
                proto = "tcp";
              }
              {
                dports = [ 4446 ];
                family = "any";
                proto = "udp";
              }
            ];
            name = "tcp-udp-4446";
          }
        ];
      };
      ownership = {
        endpoints = [
          {
            kind = "host";
            name = "edge-dns-dmz";
            tenant = "dmz";
          }
          {
            kind = "host";
            name = "edge-example-router-lighthouse";
            tenant = "dmz";
          }
          {
            kind = "host";
            name = "edge-client01";
            tenant = "client";
          }
        ];
        prefixes = [
          {
            ipv4 = "10.90.10.0/24";
            ipv6 = "fd42:dead:cafe:10::/64";
            kind = "tenant";
            name = "dmz";
          }
          {
            ipv4 = "10.90.20.0/24";
            ipv6 = "fd42:dead:cafe:20::/64";
            kind = "tenant";
            name = "client";
            routedPrefixes = [
              {
                allocation = "runtime";
                family = "ipv6";
                name = "edge-client-public";
                prefixPostfix = "4446";
                delegatedPrefixLength = 64;
                perTenantPrefixLength = 64;
                slot = 0;
                sourceFile = "/run/secrets/access-node-ipv6-prefix-esp-edge-example-router-access-client";
              }
            ];
          }
        ];
      };
      pools = {
        overlay = {
          ipv4 = {
            offsetStart = 10;
            perNodePrefixLength = 32;
            prefix = "100.96.10.0/24";
          };
          ipv6 = {
            offsetStart = 10;
            perNodePrefixLength = 128;
            prefix = "fd42:dead:beef:ee::/64";
          };
        };
        loopback = {
          ipv4 = "10.89.0.0/24";
          ipv6 = "fd42:dead:cafe:1900::/118";
        };
        p2p = {
          ipv4 = "10.80.0.0/24";
          ipv6 = "fd42:dead:cafe:1000::/118";
        };
      };
      topology = {
        hostNatIngress = {
          enabled = true;
          targetNode = "edge-example-router-core";
          uplink = "wan";
          hostReservedPorts = [
            {
              dports = [ 22 ];
              name = "ssh";
              proto = "tcp";
            }
          ];
        };
        links = [
          [
            "edge-example-router-core"
            "edge-example-router-upstream"
          ]
          [
            "edge-example-router-nebula-core"
            "edge-example-router-upstream"
          ]
          [
            "edge-example-router-upstream"
            "edge-example-router-policy"
          ]
          [
            "edge-example-router-policy"
            "edge-example-router-downstream"
          ]
          [
            "edge-example-router-downstream"
            "edge-example-router-access-dmz"
          ]
          [
            "edge-example-router-downstream"
            "edge-example-router-access-client"
          ]
        ];
        nodes = {
          edge-example-router-access-client = {
            attachments = [
              {
                kind = "tenant";
                name = "client";
              }
            ];
            role = "access";
          };
          edge-example-router-access-dmz = {
            attachments = [
              {
                kind = "tenant";
                name = "dmz";
              }
            ];
            role = "access";
          };
          edge-example-router-core = {
            role = "core";
            uplinks = {
              wan = {
                ipv4 = [ "0.0.0.0/0" ];
                ipv6 = [ "::/0" ];
              };
            };
          };
          edge-example-router-downstream = {
            role = "downstream-selector";
          };
          edge-example-router-nebula-core = {
            role = "core";
            uplinks = {
              east-west = {
                ipv4 = [
                  "10.20.70.0/24"
                  "10.50.20.0/24"
                  "10.50.70.0/24"
                  "10.70.10.0/24"
                ];
                ipv6 = [
                  "fd42:dead:beef:70::/64"
                  "fd42:dead:feed:20::/64"
                  "fd42:dead:feed:70::/64"
                  "fd42:dead:feed:7000::/56"
                ];
              };
            };
          };
          edge-example-router-policy = {
            role = "policy";
          };
          edge-example-router-upstream = {
            role = "upstream-selector";
          };
        };
      };
      transport = {
        overlays = [
          {
            mustTraverse = [ "policy" ];
            name = "east-west";
            peerSites = [
              "esp.home"
              "esp.lab"
            ];
            terminateOn = "edge-example-router-nebula-core";
            underlayAccess = {
              kind = "tenant";
              name = "client";
            };
          }
        ];
      };
    };
    lab = {
      communicationContract = {
        interfaceTags = {
          external-east-west = "east-west";
          external-wan = "wan";
          service-lab-site-dns = "lab-site-dns";
          service-lab-client-4445 = "lab-client-4445";
          service-cast-control = "cast-control";
          service-cast-discovery = "cast-discovery";
          tenant-admin = "admin";
          tenant-client = "client";
          tenant-dmz = "dmz";
          tenant-hostile = "hostile";
          tenant-mgmt = "mgmt";
          tenant-streaming = "streaming";
        };
        relations = [
          {
            action = "allow";
            from = {
              kind = "external";
              name = "wan";
            };
            id = "allow-lab-wan-icmp-anywhere";
            priority = 6;
            to = "any";
            trafficType = "icmp";
          }
          {
            action = "allow";
            from = {
              kind = "external";
              name = "east-west";
            };
            id = "allow-lab-overlay-icmp-anywhere";
            priority = 7;
            to = "any";
            trafficType = "icmp";
          }
          {
            action = "allow";
            from = {
              kind = "tenant-set";
              members = [ "admin" ];
            };
            id = "allow-admin-to-mgmt";
            priority = 10;
            to = {
              kind = "tenant-set";
              members = [ "mgmt" ];
            };
            trafficType = "any";
          }
          {
            action = "deny";
            from = {
              kind = "tenant-set";
              members = [
                "client"
                "streaming"
                "dmz"
                "hostile"
              ];
            };
            id = "deny-production-to-mgmt";
            priority = 11;
            to = {
              kind = "tenant-set";
              members = [ "mgmt" ];
            };
            trafficType = "any";
          }
          {
            action = "deny";
            from = {
              kind = "tenant-set";
              members = [ "streaming" ];
            };
            id = "deny-streaming-to-client";
            priority = 12;
            to = {
              kind = "tenant-set";
              members = [ "client" ];
            };
            trafficType = "any";
          }
          {
            action = "deny";
            from = {
              kind = "tenant-set";
              members = [ "hostile" ];
            };
            id = "deny-hostile-to-local-tenants";
            priority = 13;
            to = {
              kind = "tenant-set";
              members = [
                "admin"
                "client"
                "streaming"
                "dmz"
              ];
            };
            trafficType = "any";
          }
          {
            action = "allow";
            from = {
              kind = "tenant-set";
              members = [
                "admin"
                "client"
                "streaming"
                "dmz"
              ];
            };
            id = "allow-normal-tenants-to-lab-dns";
            priority = 20;
            to = {
              kind = "service";
              name = "lab-site-dns";
            };
            trafficType = "dns";
          }
          {
            action = "deny";
            from = {
              kind = "tenant-set";
              members = [
                "admin"
                "client"
                "streaming"
                "dmz"
              ];
            };
            id = "deny-normal-tenant-dns-to-wan";
            priority = 25;
            to = {
              kind = "external";
              name = "wan";
            };
            trafficType = "dns";
          }
          {
            action = "allow";
            from = {
              kind = "tenant-set";
              members = [ "client" ];
            };
            id = "allow-client-to-cast-discovery";
            priority = 30;
            to = {
              kind = "service";
              name = "cast-discovery";
            };
            trafficType = "cast-discovery";
          }
          {
            action = "allow";
            from = {
              kind = "tenant-set";
              members = [ "client" ];
            };
            id = "allow-client-to-cast-control";
            priority = 31;
            to = {
              kind = "service";
              name = "cast-control";
            };
            trafficType = "cast-control";
          }
          {
            action = "allow";
            from = {
              kind = "tenant-set";
              members = [
                "admin"
                "client"
                "streaming"
                "dmz"
              ];
            };
            id = "allow-normal-tenants-to-wan";
            priority = 100;
            to = {
              kind = "external";
              name = "wan";
            };
            trafficType = "any";
          }
          {
            action = "deny";
            from = {
              kind = "tenant-set";
              members = [ "hostile" ];
            };
            id = "deny-hostile-to-local-wan";
            priority = 101;
            to = {
              kind = "external";
              name = "wan";
            };
            trafficType = "any";
          }
          {
            action = "allow";
            from = {
              kind = "tenant-set";
              members = [ "hostile" ];
            };
            id = "allow-hostile-dns-to-edge-public-dns";
            priority = 110;
            to = {
              kind = "external";
              name = "east-west";
            };
            trafficType = "dns";
          }
          {
            action = "allow";
            from = {
              kind = "tenant-set";
              members = [ "hostile" ];
            };
            id = "allow-hostile-egress-to-edge-overlay";
            priority = 111;
            to = {
              kind = "external";
              name = "east-west";
            };
            trafficType = "any";
          }
          {
            action = "allow";
            from = {
              kind = "external";
              name = "east-west";
            };
            id = "allow-edge-public-4445-to-lab-client";
            priority = 120;
            to = {
              kind = "service";
              name = "lab-client-4445";
            };
            trafficType = "tcp-udp-4445";
          }
          {
            action = "allow";
            from = {
              kind = "external";
              name = "east-west";
            };
            id = "allow-nebula-underlay-to-wan";
            priority = 130;
            to = {
              kind = "external";
              uplinks = [ "wan" ];
            };
            trafficType = "nebula";
          }
        ];
        services = [
          {
            name = "lab-site-dns";
            providers = [ "lab-site-dns" ];
            trafficType = "dns";
          }
          {
            name = "lab-client-4445";
            providers = [ "lab-client01" ];
            trafficType = "tcp-udp-4445";
          }
          {
            name = "cast-control";
            providers = [ "lab-streaming01" ];
            trafficType = "cast-control";
          }
          {
            name = "cast-discovery";
            providers = [ "lab-streaming01" ];
            trafficType = "cast-discovery";
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
                dports = [ 4242 ];
                family = "any";
                proto = "tcp";
              }
              {
                dports = [ 4242 ];
                family = "any";
                proto = "udp";
              }
            ];
            name = "nebula";
          }
          {
            match = [
              {
                dports = [ 4445 ];
                family = "any";
                proto = "tcp";
              }
              {
                dports = [ 4445 ];
                family = "any";
                proto = "udp";
              }
            ];
            name = "tcp-udp-4445";
          }
          {
            match = [
              {
                dports = [
                  8008
                  8009
                ];
                family = "any";
                proto = "tcp";
              }
            ];
            name = "cast-control";
          }
          {
            match = [
              {
                dports = [ 5353 ];
                family = "any";
                proto = "udp";
              }
              {
                dports = [ 1900 ];
                family = "any";
                proto = "udp";
              }
            ];
            name = "cast-discovery";
          }
        ];
      };
      ownership = {
        endpoints = [
          {
            kind = "host";
            name = "lab-site-dns";
            tenant = "mgmt";
          }
          {
            kind = "host";
            name = "lab-client01";
            tenant = "client";
          }
          {
            kind = "host";
            name = "lab-client02";
            tenant = "client";
          }
          {
            kind = "host";
            name = "lab-streaming01";
            tenant = "streaming";
          }
          {
            kind = "host";
            name = "hostile-node01";
            tenant = "hostile";
          }
        ];
        prefixes = [
          {
            ipv4 = "10.50.10.0/24";
            ipv6 = "fd42:dead:feed:10::/64";
            kind = "tenant";
            name = "mgmt";
          }
          {
            ipv4 = "10.50.15.0/24";
            ipv6 = "fd42:dead:feed:15::/64";
            kind = "tenant";
            name = "admin";
          }
          {
            ipv4 = "10.50.20.0/24";
            ipv6 = "fd42:dead:feed:20::/64";
            kind = "tenant";
            name = "client";
            routedPrefixes = [
              {
                allocation = "runtime";
                family = "ipv6";
                name = "lab-client-public";
                prefixPostfix = "4445";
                delegatedPrefixLength = 64;
                perTenantPrefixLength = 64;
                slot = 0;
                sourceFile = "/run/secrets/access-node-ipv6-prefix-esp-lab-example-router-access-client";
              }
            ];
          }
          {
            ipv4 = "10.50.30.0/24";
            ipv6 = "fd42:dead:feed:30::/64";
            kind = "tenant";
            name = "dmz";
          }
          {
            ipv4 = "10.50.50.0/24";
            ipv6 = "fd42:dead:feed:50::/64";
            kind = "tenant";
            name = "streaming";
          }
          {
            ipv4 = "10.70.10.0/24";
            ipv6 = "fd42:dead:feed:70::/64";
            kind = "tenant";
            name = "hostile";
            routedPrefixes = [
              {
                allocation = "runtime";
                family = "ipv6";
                name = "hostile-public";
                delegatedPrefixLength = 64;
                perTenantPrefixLength = 64;
                slot = 0;
                sourceFile = "/run/secrets/access-node-ipv6-prefix-esp-lab-example-router-access-hostile";
              }
            ];
          }
        ];
      };
      pools = {
        overlay = {
          ipv4 = {
            offsetStart = 10;
            perNodePrefixLength = 32;
            prefix = "100.96.10.0/24";
          };
          ipv6 = {
            offsetStart = 10;
            perNodePrefixLength = 128;
            prefix = "fd42:dead:beef:ee::/64";
          };
        };
        loopback = {
          ipv4 = "10.59.0.0/24";
          ipv6 = "fd42:dead:feed:1900::/118";
        };
        p2p = {
          ipv4 = "10.50.0.0/24";
          ipv6 = "fd42:dead:feed:1000::/118";
        };
      };
      topology = {
        links = [
          [
            "lab-example-router-core-simulated-isp"
            "lab-example-router-upstream"
          ]
          [
            "lab-example-router-core-nebula"
            "lab-example-router-upstream"
          ]
          [
            "lab-example-router-upstream"
            "lab-example-router-policy"
          ]
          [
            "lab-example-router-policy"
            "lab-example-router-downstream"
          ]
          [
            "lab-example-router-downstream"
            "lab-example-router-access-admin"
          ]
          [
            "lab-example-router-downstream"
            "lab-example-router-access-client"
          ]
          [
            "lab-example-router-downstream"
            "lab-example-router-access-dmz"
          ]
          [
            "lab-example-router-downstream"
            "lab-example-router-access-hostile"
          ]
          [
            "lab-example-router-downstream"
            "lab-example-router-access-mgmt"
          ]
          [
            "lab-example-router-downstream"
            "lab-example-router-access-streaming"
          ]
        ];
        nodes = {
          lab-example-router-access-admin = {
            attachments = [
              {
                kind = "tenant";
                name = "admin";
              }
            ];
            role = "access";
          };
          lab-example-router-access-client = {
            attachments = [
              {
                kind = "tenant";
                name = "client";
              }
            ];
            role = "access";
          };
          lab-example-router-access-dmz = {
            attachments = [
              {
                kind = "tenant";
                name = "dmz";
              }
            ];
            role = "access";
          };
          lab-example-router-access-hostile = {
            attachments = [
              {
                kind = "tenant";
                name = "hostile";
              }
            ];
            role = "access";
          };
          lab-example-router-access-mgmt = {
            attachments = [
              {
                kind = "tenant";
                name = "mgmt";
              }
            ];
            role = "access";
          };
          lab-example-router-access-streaming = {
            attachments = [
              {
                kind = "tenant";
                name = "streaming";
              }
            ];
            role = "access";
          };
          lab-example-router-core-nebula = {
            attachments = [
              {
                kind = "tenant";
                name = "client";
              }
            ];
            role = "core";
            uplinks = {
              east-west = {
                ipv4 = [
                  "10.20.10.0/24"
                  "10.20.15.0/24"
                  "10.20.20.0/24"
                  "10.20.30.0/24"
                  "10.20.50.0/24"
                  "10.90.10.0/24"
                  "0.0.0.0/0"
                ];
                ipv6 = [
                  "fd42:dead:beef:10::/64"
                  "fd42:dead:beef:15::/64"
                  "fd42:dead:beef:20::/64"
                  "fd42:dead:beef:30::/64"
                  "fd42:dead:beef:50::/64"
                  "fd42:dead:cafe:10::/64"
                  "::/0"
                ];
              };
            };
          };
          lab-example-router-core-simulated-isp = {
            role = "core";
            uplinks = {
              wan = {
                ipv4 = [ "0.0.0.0/0" ];
                ipv6 = [ "::/0" ];
              };
            };
          };
          lab-example-router-downstream = {
            role = "downstream-selector";
          };
          lab-example-router-policy = {
            role = "policy";
          };
          lab-example-router-upstream = {
            role = "upstream-selector";
          };
        };
      };
      transport = {
        overlays = [
          {
            mustTraverse = [ "policy" ];
            name = "east-west";
            peerSites = [
              "esp.home"
              "esp.edge"
            ];
            terminateOn = "lab-example-router-core-nebula";
            underlayAccess = {
              kind = "tenant";
              name = "client";
            };
          }
        ];
      };
    };
  };
}
