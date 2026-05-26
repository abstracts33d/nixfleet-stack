{
  config,
  lib,
  pkgs,
  ...
}:
lib.mkIf config.fleet.server.enable {
  services.grafana = {
    enable = true;
    # Infinity datasource queries CP /v1/* directly so per-host state surfaces
    # without widening the CP's Prometheus surface (kept minimal: counters + build_info).
    declarativePlugins = [ pkgs.grafanaPlugins.yesoreyeram-infinity-datasource ];
    settings = {
      server = {
        http_addr = "127.0.0.1"; # Caddy fronts
        http_port = 3100;
        domain = "grafana.lab.internal";
      };
      security.secret_key = "$__file{${config.age.secrets.grafana-secret-key.path}}";
      # Anonymous read on tailnet.
      "auth.anonymous" = {
        enabled = true;
        org_role = "Viewer";
      };
    };

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
            # mTLS reuses lab agent cert; CP accepts any agent cert for /v1 reads.
            tlsAuth = true;
            tlsAuthWithCACert = true;
            global_queries = [ ];
          };
          # `$__file{path}` is read at startup → keeps key material out of /nix/store.
          secureJsonData = {
            tlsCACert = "$__file{/etc/nixfleet/fleet-ca.pem}";
            tlsClientCert = "$__file{/var/lib/nixfleet/agent-cert.pem}";
            tlsClientKey = "$__file{/var/lib/nixfleet/agent-mtls-key.pem}";
          };
        }
      ];
      # allowUiUpdates=true lets browser-edits stick until restart; file in
      # ./grafana-dashboards wins on reload. Export+commit JSON to persist edits.
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

  # Grafana reads /var/lib/nixfleet/agent-mtls-key.pem (0640, nixfleet-mtls).
  # Export unit: monitoring-prometheus.nix.
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
