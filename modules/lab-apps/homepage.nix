# Catppuccin Macchiato dashboard; widget API keys come from homepage-env secret.
{
  config,
  lib,
  ...
}:
lib.mkIf config.fleet.server.enable {
  # DynamicUser breaks impermanence: persist dir created before transient user exists.
  users.users.homepage-dashboard = {
    isSystemUser = true;
    group = "homepage-dashboard";
  };
  users.groups.homepage-dashboard = { };

  services.homepage-dashboard = {
    enable = true;
    openFirewall = true;

    environmentFiles = [ config.age.secrets."homepage-env".path ];
    allowedHosts = "lab.internal,192.168.1.10,theabstractconnection.com";

    settings = {
      title = "Lab";
      theme = "dark";
      color = "slate";
      headerStyle = "clean";
      layout = {
        Infrastructure = {
          style = "row";
          columns = 3;
        };
        Media = {
          style = "row";
          columns = 2;
        };
        Monitoring = {
          style = "row";
          columns = 3;
        };
        Automation = {
          style = "row";
          columns = 2;
        };
      };
    };

    widgets = [
      {
        resources = {
          cpu = true;
          memory = true;
          disk = "/persist";
        };
      }
    ];

    services = [
      {
        Infrastructure = [
          {
            AdGuard = {
              icon = "adguard-home.svg";
              href = "https://adguard.lab.internal";
              description = "DNS ad-blocking";
              widget = {
                type = "adguard";
                url = "https://adguard.lab.internal";
              };
            };
          }
          {
            Tailscale = {
              icon = "tailscale.svg";
              href = "https://login.tailscale.com/admin/machines";
              description = "Mesh VPN";
            };
          }
          {
            Prometheus = {
              icon = "prometheus.svg";
              href = "https://prometheus.lab.internal";
              description = "Metrics";
              widget = {
                type = "prometheus";
                url = "https://prometheus.lab.internal";
              };
            };
          }
        ];
      }
      {
        Media = [
          {
            Jellyfin = {
              icon = "jellyfin.svg";
              href = "https://jellyfin.lab.internal";
              description = "Media server";
              widget = {
                type = "jellyfin";
                url = "https://jellyfin.lab.internal";
                key = "{{HOMEPAGE_VAR_JELLYFIN_KEY}}";
              };
            };
          }
          {
            Immich = {
              icon = "immich.svg";
              href = "https://immich.lab.internal";
              description = "Photo management";
              widget = {
                type = "immich";
                url = "https://immich.lab.internal";
                key = "{{HOMEPAGE_VAR_IMMICH_KEY}}";
                version = 2;
              };
            };
          }
          {
            Samba = {
              icon = "mdi-folder-network";
              href = "https://lab.internal";
              description = "Shared files (~/shared/)";
            };
          }
        ];
      }
      {
        Monitoring = [
          {
            Grafana = {
              icon = "grafana.svg";
              href = "https://grafana.lab.internal";
              description = "Dashboards";
            };
          }
          {
            "Service Probes" = {
              icon = "prometheus.svg";
              href = "https://grafana.lab.internal";
              description = "Blackbox HTTP probes";
            };
          }
          {
            Restic = {
              icon = "mdi-backup-restore";
              href = "https://restic.lab.internal";
              description = "Backup server";
            };
          }
        ];
      }
      {
        Automation = [
          {
            "Home Assistant" = {
              icon = "home-assistant.svg";
              href = "https://hass.lab.internal";
              description = "Home automation";
              widget = {
                type = "homeassistant";
                url = "https://hass.lab.internal";
                key = "{{HOMEPAGE_VAR_HASS_KEY}}";
              };
            };
          }
          {
            "Atuin Sync" = {
              icon = "atuin.svg";
              href = "https://atuin.lab.internal";
              description = "Shell history sync";
            };
          }
        ];
      }
    ];

    customCSS = ''
      :root {
        --color-50: #f4f0f8;
        --color-100: #e6e1ec;
        --color-200: #c6bdd5;
        --color-300: #a99dbe;
        --color-400: #8c7da7;
        --color-500: #7060a0;
        --color-600: #5b4d82;
        --color-700: #453a63;
        --color-800: #24273a;
        --color-900: #1e2030;
        --color-950: #181926;
      }
      body {
        background-color: #24273a !important;
        color: #cad3f5 !important;
      }
      .service-card {
        background-color: #1e2030 !important;
      }
      .widget {
        background-color: #1e2030 !important;
      }
    '';
  };

  systemd.services.homepage-dashboard.serviceConfig.DynamicUser = lib.mkForce false;

  nixfleet.persistence.directories = [
    {
      directory = "/var/lib/homepage-dashboard";
      user = "homepage-dashboard";
      group = "homepage-dashboard";
    }
  ];
}
