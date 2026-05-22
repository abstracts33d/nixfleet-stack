# Blackbox exporter + probe scrape job — folded into monitoring-server.
# Consumers declare a list of probes; the module generates the blackbox
# config and a Prometheus scrape job targeting them.
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixfleet.monitoring.server.blackbox;
  inherit (lib) types;

  blackboxModules = {
    http_2xx = {
      prober = "http";
      timeout = "5s";
      http = {
        follow_redirects = true;
        preferred_ip_protocol = "ip4";
      };
    };
    http_any = {
      prober = "http";
      timeout = "5s";
      http = {
        valid_status_codes = [
          200
          301
          302
          400
          401
          403
          404
          405
          500
        ];
        preferred_ip_protocol = "ip4";
      };
    };
    tcp_connect = {
      prober = "tcp";
      timeout = "5s";
    };
  };
in
{
  options.nixfleet.monitoring.server.blackbox = {
    enable = lib.mkEnableOption "blackbox exporter and HTTP/TCP probe scrape job";

    port = lib.mkOption {
      type = types.port;
      default = 9115;
      description = "Blackbox exporter listen port.";
    };

    probes = lib.mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            name = lib.mkOption {
              type = types.str;
              description = "Probe label (used as the `service` label in metrics).";
            };
            target = lib.mkOption {
              type = types.str;
              description = "Target URL or host:port to probe (e.g. http://localhost:8080, lab:22).";
            };
            module = lib.mkOption {
              type = types.enum (lib.attrNames blackboxModules);
              default = "http_2xx";
              description = "Blackbox module to use for this probe.";
            };
          };
        }
      );
      default = [ ];
      description = "List of probe targets.";
    };
  };

  config = lib.mkIf (config.nixfleet.monitoring.server.enable && cfg.enable) {
    services.prometheus = {
      exporters.blackbox = {
        enable = true;
        inherit (cfg) port;
        configFile = builtins.toFile "blackbox.yml" (builtins.toJSON { modules = blackboxModules; });
      };

      scrapeConfigs = [
        {
          job_name = "blackbox";
          metrics_path = "/probe";
          static_configs = map (p: {
            targets = [ p.target ];
            labels = {
              service = p.name;
              "__param_module" = p.module;
            };
          }) cfg.probes;
          relabel_configs = [
            {
              source_labels = [ "__address__" ];
              target_label = "__param_target";
            }
            {
              source_labels = [ "service" ];
              target_label = "instance";
            }
            {
              target_label = "__address__";
              replacement = "127.0.0.1:${toString cfg.port}";
            }
          ];
        }
      ];
    };
  };
}
