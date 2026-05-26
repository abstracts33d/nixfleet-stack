{
  config,
  lib,
  ...
}:
let
  cfg = config.nixfleet.monitoring.server;

  builtinAlerts = {
    groups = [
      {
        name = "nixfleet";
        rules = [
          {
            alert = "HostDown";
            expr = "up == 0";
            "for" = "1m";
            labels.severity = "critical";
            annotations.summary = "{{ $labels.instance }} is unreachable";
          }
          {
            alert = "DiskSpaceHigh";
            expr = ''node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} < 0.2'';
            "for" = "5m";
            labels.severity = "warning";
            annotations.summary = "{{ $labels.instance }} root disk > 80% full";
          }
          {
            alert = "SystemdUnitFailed";
            expr = ''node_systemd_unit_state{state="failed"} == 1'';
            "for" = "1m";
            labels.severity = "warning";
            annotations.summary = "{{ $labels.name }} failed on {{ $labels.instance }}";
          }
        ]
        ++ lib.optionals cfg.alerts.controlPlane [
          {
            alert = "ControlPlaneDown";
            expr = ''up{job="nixfleet-cp"} == 0'';
            "for" = "1m";
            labels.severity = "critical";
            annotations.summary = "NixFleet control plane is unreachable";
          }
          {
            alert = "RollbackFiring";
            expr = "rate(nixfleet_compliance_failure_events_total[15m]) > 0";
            "for" = "0m";
            labels.severity = "critical";
            annotations.summary = "Compliance failure events arriving — investigate /v1/host-reports";
          }
          {
            alert = "GateBlockSpike";
            expr = "sum by (gate) (rate(nixfleet_gate_block_total[1h])) > 10";
            "for" = "5m";
            labels.severity = "warning";
            annotations.summary = "Gate-block rate >10/h on gate {{ $labels.gate }} — stuck rollout?";
          }
        ]
        ++ lib.optionals cfg.alerts.coordinator [
          {
            alert = "CoordinatorForgeDown";
            expr = ''probe_success{service="forge"} == 0'';
            "for" = "2m";
            labels.severity = "critical";
            annotations.summary = "Coordinator forge (Forgejo) is unreachable";
          }
          {
            alert = "CoordinatorCacheDown";
            expr = ''probe_success{service="cache"} == 0'';
            "for" = "2m";
            labels.severity = "critical";
            annotations.summary = "Coordinator binary cache (attic) is unreachable";
          }
          {
            alert = "CoordinatorCiRunnerDown";
            expr = ''up{job="gitea-runner"} == 0'';
            "for" = "5m";
            labels.severity = "warning";
            annotations.summary = "Coordinator CI runner is offline";
          }
        ];
      }
    ];
  };
in
{
  imports = [ ./blackbox.nix ];
  options.nixfleet.monitoring.server = {
    enable = lib.mkEnableOption "Prometheus server with fleet defaults";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "Prometheus listen port.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Prometheus listen address. Use 0.0.0.0 to expose externally.";
    };

    retentionTime = lib.mkOption {
      type = lib.types.str;
      default = "30d";
      description = "TSDB retention period.";
    };

    scrapeInterval = lib.mkOption {
      type = lib.types.str;
      default = "15s";
      description = "Global scrape interval.";
    };

    targets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Static node-exporter targets (e.g., ["web-01:9100" "db-01:9100"]).
        Auto-generates a "node" scrape job.
      '';
    };

    extraScrapeConfigs = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      description = "Additional Prometheus scrape configs (appended to built-in ones).";
    };

    alerts = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable built-in alert rules (HostDown, DiskSpaceHigh, SystemdUnitFailed).";
      };

      controlPlane = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Add control-plane alerts (ControlPlaneDown / RollbackFiring / GateBlockSpike). Requires the nixfleet-cp scrape job + counter metrics.";
      };

      coordinator = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Add coordinator alerts (forge/cache blackbox probes + CI runner up). Requires matching blackbox probes or scrape jobs.";
      };

      extraRuleFiles = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [ ];
        description = "Additional Prometheus rule files.";
      };
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open Prometheus port in the firewall.";
    };

    alertmanager = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Prometheus Alertmanager + point the Prometheus server at it. Routes alerts to ntfy via webhook.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 9093;
        description = "Alertmanager listen port (loopback only).";
      };

      ntfyPort = lib.mkOption {
        type = lib.types.port;
        default = 2586;
        description = "ntfy listen port — Alertmanager POSTs webhook payloads here.";
      };

      ntfyTopic = lib.mkOption {
        type = lib.types.str;
        default = "nixfleet-alerts";
        description = "ntfy topic name for fleet alerts. Subscribe via the ntfy app or `curl -s https://ntfy.lab.internal/<topic>/json`.";
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        services.prometheus = {
          enable = true;
          inherit (cfg) port;
          inherit (cfg) listenAddress;
          globalConfig.scrape_interval = cfg.scrapeInterval;
          checkConfig = "syntax-only";
          inherit (cfg) retentionTime;

          ruleFiles =
            (lib.optional cfg.alerts.enable (
              builtins.toFile "nixfleet-alerts.yml" (builtins.toJSON builtinAlerts)
            ))
            ++ cfg.alerts.extraRuleFiles;

          scrapeConfigs =
            (lib.optional (cfg.targets != [ ]) {
              job_name = "node";
              static_configs = [ { inherit (cfg) targets; } ];
              # Strip port from `instance` into a `hostname` label so Grafana
              # data links can pass clean `?var-hostname=<host>`.
              relabel_configs = [
                {
                  source_labels = [ "instance" ];
                  regex = "(.+):[0-9]+";
                  target_label = "hostname";
                  replacement = "$1";
                }
              ];
            })
            ++ cfg.extraScrapeConfigs;

          alertmanagers = lib.optional cfg.alertmanager.enable {
            static_configs = [ { targets = [ "127.0.0.1:${toString cfg.alertmanager.port}" ]; } ];
          };
        };

        services.prometheus.alertmanager = lib.mkIf cfg.alertmanager.enable {
          enable = true;
          listenAddress = "127.0.0.1";
          inherit (cfg.alertmanager) port;
          configuration = {
            route = {
              receiver = "ntfy";
              # 30s wait absorbs bursts; 5m group_interval / 1h repeat keep
              # ongoing alerts visible without nagging.
              group_by = [
                "alertname"
                "severity"
              ];
              group_wait = "30s";
              group_interval = "5m";
              repeat_interval = "1h";
            };
            receivers = [
              {
                name = "ntfy";
                webhook_configs = [
                  {
                    url = "http://127.0.0.1:${toString cfg.alertmanager.ntfyPort}/${cfg.alertmanager.ntfyTopic}";
                    send_resolved = true;
                  }
                ];
              }
            ];
          };
        };
      }

      (lib.mkIf cfg.openFirewall {
        networking.firewall.allowedTCPPorts = [ cfg.port ];
      })

      {
        nixfleet.persistence.directories = [
          {
            directory = "/var/lib/prometheus2";
            user = "prometheus";
            group = "prometheus";
            mode = "0700";
          }
        ];
      }
    ]
  );
}
