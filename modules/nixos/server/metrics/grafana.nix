_:
let
  domain = "grafana.goosebox.org";
in
{
  flake = {
    monitoringChecks.grafana = {
      name = "grafana";
      url = "https://${domain}/api/health";
    };

    modules.nixos = {
      grafana =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.blizzard.grafana;
          prometheus = config.services.prometheus;

          panel =
            {
              title,
              exprs,
              unit,
              x,
              y,
              w ? 12,
              h ? 8,
              max ? null,
            }:
            {
              inherit title;
              type = "timeseries";
              datasource.uid = "prometheus";
              gridPos = {
                inherit
                  x
                  y
                  w
                  h
                  ;
              };
              fieldConfig.defaults = {
                inherit unit;
                custom.fillOpacity = 10;
              }
              // lib.optionalAttrs (max != null) {
                inherit max;
                min = 0;
              };
              options.legend = {
                displayMode = "table";
                placement = "right";
                calcs = [
                  "lastNotNull"
                  "max"
                ];
              };
              targets = lib.imap0 (i: target: {
                refId = lib.elemAt [ "A" "B" "C" ] i;
                inherit (target) expr;
                legendFormat = target.legend;
              }) exprs;
            };

          services = ''id=~".+\\.service", id!~".*/user@[0-9]+\\.service", host=~"$host"'';
          short = expr: ''label_replace(${expr}, "unit", "$1", "id", ".*/(.+)\\.service")'';

          overview = {
            uid = "blizzard-overview";
            title = "Overview";
            refresh = "1m";
            time.from = "now-24h";
            schemaVersion = 39;
            templating.list = [
              {
                name = "host";
                type = "query";
                datasource.uid = "prometheus";
                query = "label_values(up, host)";
                multi = true;
                includeAll = true;
                current = {
                  text = "All";
                  value = "$__all";
                };
              }
            ];
            panels = [
              (panel {
                title = "CPU busy";
                unit = "percentunit";
                max = 1;
                x = 0;
                y = 0;
                exprs = [
                  {
                    expr = ''1 - avg by (host) (rate(node_cpu_seconds_total{mode="idle", host=~"$host"}[$__rate_interval]))'';
                    legend = "{{host}}";
                  }
                ];
              })
              (panel {
                title = "Memory free (ZFS ARC counted free)";
                unit = "percentunit";
                max = 1;
                x = 12;
                y = 0;
                exprs = [
                  {
                    expr = ''(node_memory_MemAvailable_bytes{host=~"$host"} + node_zfs_arc_size or node_memory_MemAvailable_bytes{host=~"$host"}) / node_memory_MemTotal_bytes'';
                    legend = "{{host}}";
                  }
                ];
              })
              (panel {
                title = "Disk used";
                unit = "percentunit";
                max = 1;
                x = 0;
                y = 8;
                exprs = [
                  {
                    expr = ''1 - node_filesystem_avail_bytes{fstype!~"tmpfs|ramfs|squashfs|overlay|fuse.*", mountpoint!~"/run/restic-zfs/.*", host=~"$host"} / node_filesystem_size_bytes'';
                    legend = "{{host}} {{mountpoint}}";
                  }
                ];
              })
              (panel {
                title = "Pressure stall";
                unit = "percentunit";
                x = 12;
                y = 8;
                exprs = [
                  {
                    expr = ''rate(node_pressure_cpu_waiting_seconds_total{host=~"$host"}[$__rate_interval])'';
                    legend = "{{host}} cpu";
                  }
                  {
                    expr = ''rate(node_pressure_memory_waiting_seconds_total{host=~"$host"}[$__rate_interval])'';
                    legend = "{{host}} memory";
                  }
                  {
                    expr = ''rate(node_pressure_io_waiting_seconds_total{host=~"$host"}[$__rate_interval])'';
                    legend = "{{host}} io";
                  }
                ];
              })
              (panel {
                title = "Top services by memory";
                unit = "bytes";
                x = 0;
                y = 16;
                exprs = [
                  {
                    expr = "topk(10, ${short "container_memory_working_set_bytes{${services}}"})";
                    legend = "{{host}} {{unit}}";
                  }
                ];
              })
              (panel {
                title = "Top services by CPU (cores)";
                unit = "short";
                x = 12;
                y = 16;
                exprs = [
                  {
                    expr = "topk(10, ${short "rate(container_cpu_usage_seconds_total{${services}}[$__rate_interval])"})";
                    legend = "{{host}} {{unit}}";
                  }
                ];
              })
              (panel {
                title = "Network";
                unit = "Bps";
                x = 0;
                y = 24;
                exprs = [
                  {
                    expr = ''sum by (host) (rate(node_network_receive_bytes_total{device!~"lo|veth.*|podman.*", host=~"$host"}[$__rate_interval]))'';
                    legend = "{{host}} in";
                  }
                  {
                    expr = ''-sum by (host) (rate(node_network_transmit_bytes_total{device!~"lo|veth.*|podman.*", host=~"$host"}[$__rate_interval]))'';
                    legend = "{{host}} out";
                  }
                ];
              })
              (panel {
                title = "OOM kills";
                unit = "short";
                x = 12;
                y = 24;
                exprs = [
                  {
                    expr = ''increase(node_vmstat_oom_kill{host=~"$host"}[1h])'';
                    legend = "{{host}} kernel";
                  }
                  {
                    expr = ''sum by (host, id) (increase(container_oom_events_total{host=~"$host"}[1h])) > 0'';
                    legend = "{{host}} {{id}}";
                  }
                ];
              })
            ];
          };

          dashboards = pkgs.linkFarm "grafana-dashboards" [
            {
              name = "overview.json";
              path = pkgs.writeText "overview.json" (builtins.toJSON overview);
            }
          ];
        in
        {
          options.blizzard.grafana = {
            port = lib.mkOption {
              type = lib.types.port;
              default = 3005;
            };

            secretKeyFile = lib.mkOption {
              type = lib.types.path;
              description = "Key Grafana encrypts its database secrets with.";
            };

            adminPasswordFile = lib.mkOption {
              type = lib.types.path;
              description = "Password for the admin login, which edits dashboards.";
            };
          };

          config = {
            services.grafana = {
              enable = true;
              # Grafana fetches these from grafana.com otherwise.
              declarativePlugins = [
                pkgs.grafanaPlugins.prometheus
                pkgs.grafanaPlugins.grafana-metricsdrilldown-app
              ];
              settings = {
                server = {
                  http_addr = "127.0.0.1";
                  http_port = cfg.port;
                  inherit domain;
                  root_url = "https://${domain}";
                };
                security = {
                  admin_user = "admin";
                  admin_password = "$__file{${cfg.adminPasswordFile}}";
                  secret_key = "$__file{${cfg.secretKeyFile}}";
                  cookie_secure = true;
                };
                # The tailnet is the gate; log in only to edit.
                "auth.anonymous" = {
                  enabled = true;
                  org_role = "Viewer";
                };
                users.allow_sign_up = false;
                analytics = {
                  reporting_enabled = false;
                  check_for_updates = false;
                  check_for_plugin_updates = false;
                };
              };

              provision = {
                enable = true;
                datasources.settings.datasources = [
                  {
                    name = "Prometheus";
                    type = "prometheus";
                    uid = "prometheus";
                    url = "http://${prometheus.listenAddress}:${toString prometheus.port}";
                    isDefault = true;
                  }
                ];
                dashboards.settings.providers = [
                  {
                    name = "blizzard";
                    # Edits in the UI vanish on restart; change them here.
                    allowUiUpdates = false;
                    options.path = dashboards;
                  }
                ];
              };
            };

            systemd.services.grafana.unitConfig.OnFailure = "alert-failure@grafana.service";

            services.nginx.virtualHosts.${domain} = {
              enableACME = true;
              forceSSL = true;
              locations."/" = {
                proxyPass = "http://127.0.0.1:${toString cfg.port}";
                proxyWebsockets = true;
              };
            };
          };
        };

      grafana-secrets =
        { config, ... }:
        let
          secret = file: {
            rekeyFile = file;
            generator.script = "alnum";
            owner = "grafana";
          };
        in
        {
          age.secrets = {
            grafana-secret-key = secret ./secrets/grafana-secret-key.age;
            grafana-admin-password = secret ./secrets/grafana-admin-password.age;
          };

          blizzard.grafana = {
            secretKeyFile = config.age.secrets.grafana-secret-key.path;
            adminPasswordFile = config.age.secrets.grafana-admin-password.path;
          };
        };
    };
  };
}
