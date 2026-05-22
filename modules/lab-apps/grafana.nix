# Grafana — dashboards wired to Prometheus + the Infinity JSON datasource
# for live CP API queries (server only).
{
  config,
  lib,
  pkgs,
  ...
}:
lib.mkIf config.fleet.server.enable {
  services.grafana = {
    enable = true;
    # Infinity lets dashboards query the CP's `/v1/*` JSON endpoints directly,
    # which is how per-host/per-rollout state surfaces in the UI without
    # widening the CP's Prometheus metrics surface (kept intentionally minimal —
    # counters + build_info only).
    declarativePlugins = [ pkgs.grafanaPlugins.yesoreyeram-infinity-datasource ];
    settings = {
      server = {
        http_addr = "127.0.0.1"; # accessed via Caddy
        http_port = 3100;
        domain = "grafana.lab.internal";
      };
      security.secret_key = "$__file{${config.age.secrets.grafana-secret-key.path}}";
      # Anonymous read access for local/tailnet use
      "auth.anonymous" = {
        enabled = true;
        org_role = "Viewer";
      };
    };

    # Auto-provision Prometheus datasource
    provision = {
      enable = true;
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          uid = "PBFA97CFB590B2093";
          url = "http://localhost:9090";
          isDefault = true;
          editable = false;
        }
        {
          name = "NixFleet CP";
          type = "yesoreyeram-infinity-datasource";
          uid = "nixfleet-cp";
          url = "https://lab:8080";
          isDefault = false;
          editable = false;
          jsonData = {
            # mTLS against the CP. Reuses the lab agent cert; the CP accepts
            # any agent client cert for read-only /v1 endpoints.
            tlsAuth = true;
            tlsAuthWithCACert = true;
            global_queries = [ ];
          };
          # `$__file{path}` is replaced at startup with the file contents — keeps
          # the key material out of /nix/store and out of any provisioning YAML.
          secureJsonData = {
            tlsCACert = "$__file{/etc/nixfleet/fleet-ca.pem}";
            tlsClientCert = "$__file{/var/lib/nixfleet/agent-cert.pem}";
            tlsClientKey = "$__file{/var/lib/nixfleet/agent-mtls-key.pem}";
          };
        }
      ];
      # `allowUiUpdates = true` so dashboards can be tuned in the
      # browser; the file in `./grafana-dashboards` still wins on
      # Grafana restart (it's the source of truth in git). To persist
      # browser edits: export the dashboard JSON via the UI and commit
      # it back to this directory. Flip to `false` once the dashboard
      # is stable to lock it down.
      dashboards.settings.providers = [
        {
          name = "Fleet";
          type = "file";
          options.path = ./grafana-dashboards;
          options.foldersFromFilesStructure = false;
          allowUiUpdates = true;
        }
      ];
    };
  };

  # Port not opened — accessed via Caddy reverse proxy

  # Grafana needs read on /var/lib/nixfleet/agent-mtls-key.pem (mode 0640,
  # group nixfleet-mtls). The export unit lives in monitoring-prometheus.nix.
  users.users.grafana.extraGroups = [ "nixfleet-mtls" ];
  systemd.services.grafana.after = [ "nixfleet-agent-mtls-key-export.service" ];

  nixfleet.persistence.directories = [
    {
      directory = "/var/lib/grafana";
      user = "grafana";
      group = "grafana";
      mode = "0700";
    }
  ];
}
