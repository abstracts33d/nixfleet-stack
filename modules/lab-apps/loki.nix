{
  config,
  lib,
  fleetServices,
  ...
}:
let
  inherit (fleetServices.loki) port;
in
lib.mkIf config.fleet.server.enable {
  services.loki = {
    enable = true;
    configuration = {
      auth_enabled = false;
      server = {
        http_listen_address = "0.0.0.0";
        http_listen_port = port;
        grpc_listen_port = 0;
      };
      common = {
        path_prefix = "/var/lib/loki";
        storage.filesystem = {
          chunks_directory = "/var/lib/loki/chunks";
          rules_directory = "/var/lib/loki/rules";
        };
        replication_factor = 1;
        ring.instance_addr = "127.0.0.1";
        ring.kvstore.store = "inmemory";
      };
      schema_config.configs = [
        {
          from = "2026-01-01";
          store = "tsdb";
          object_store = "filesystem";
          schema = "v13";
          index = {
            prefix = "index_";
            period = "24h";
          };
        }
      ];
      # 14-day retention (336h).
      limits_config = {
        retention_period = "336h";
        allow_structured_metadata = true;
      };
      compactor = {
        working_directory = "/var/lib/loki/compactor";
        retention_enabled = true;
        delete_request_store = "filesystem";
      };
      analytics.reporting_enabled = false;
    };
  };

  networking.firewall.allowedTCPPorts = [ port ];

  nixfleet.persistence.directories = [
    {
      directory = "/var/lib/loki";
      user = "loki";
      group = "loki";
      mode = "0700";
    }
  ];

  services.grafana.provision.datasources.settings.datasources = [
    {
      name = "Loki";
      type = "loki";
      uid = "loki-lab";
      url = "http://127.0.0.1:${toString port}";
      editable = false;
    }
  ];
}
