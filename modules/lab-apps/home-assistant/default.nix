# PostgreSQL recorder (not SQLite); HACS needs configWritable. Initial setup via web UI.
{
  config,
  lib,
  ...
}:
{
  imports = [ ./msunpv.nix ];

  config = lib.mkIf config.fleet.server.enable {
    services.home-assistant = {
      enable = true;
      openFirewall = true; # phones hit IP:8123 directly on LAN/Tailscale
      configWritable = true; # HACS writes here
      extraPackages = ps: [
        ps.psycopg2
        (ps.callPackage ../../../packages/hyxi-cloud-api.nix { })
      ];

      extraComponents = [
        "default_config"
        "met"
        "zha"
        "esphome"
        "recorder"
        "prometheus"
        "mobile_app"
      ];

      config = {
        default_config = { };
        homeassistant = {
          name = "Home";
          unit_system = "metric";
          time_zone = "Europe/Paris";
          latitude = "!secret latitude";
          longitude = "!secret longitude";
        };
        recorder.db_url = "postgresql://@/hass";
        prometheus = { };
        http = {
          server_host = "0.0.0.0";
          server_port = 8123;
          use_x_forwarded_for = true;
          trusted_proxies = [
            "127.0.0.1"
            "::1"
          ];
        };
      };
    };

    services.postgresql = {
      enable = true;
      ensureDatabases = [ "hass" ];
      ensureUsers = [
        {
          name = "hass";
          ensureDBOwnership = true;
        }
      ];
    };

    nixfleet.persistence.directories = [
      {
        directory = "/var/lib/hass";
        user = "hass";
        group = "hass";
        mode = "0700";
      }
    ];
  };
}
