# osquery agent — NixOS variant. Wraps services.osquery with tier-B allowlist
# packs, dual logging (TLS to fleet-dm + filesystem to Vector→Loki), and a
# daily compliance-evidence timer feeding nixfleet-compliance.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixfleet.osquery;

  packs = pkgs.runCommand "osquery-packs" { } ''
    mkdir -p $out
    cp ${./query-packs}/inventory.conf $out/
    cp ${./query-packs}/runtime.conf $out/
    cp ${./query-packs}/compliance.conf $out/
    ${lib.optionalString (cfg.hostTier == "server") ''
      cp ${./query-packs}/lab-extras.conf $out/
    ''}
  '';

  configJson = pkgs.writeText "osquery.conf" (builtins.toJSON {
    options = {
      tls_hostname = lib.removePrefix "https://" (lib.removePrefix "http://" cfg.fleetDmUrl);
      enroll_secret_path = toString cfg.enrollSecretFile;
      enroll_tls_endpoint = "/api/v1/osquery/enroll";
      config_plugin = "tls";
      config_tls_endpoint = "/api/v1/osquery/config";
      config_tls_refresh = "60";
      logger_plugin = "tls,filesystem";
      logger_tls_endpoint = "/api/v1/osquery/log";
      logger_tls_period = "10";
      logger_path = builtins.dirOf cfg.logForwarding.lokiFile;
      disable_distributed = false;
      distributed_plugin = "tls";
      distributed_tls_read_endpoint = "/api/v1/osquery/distributed/read";
      distributed_tls_write_endpoint = "/api/v1/osquery/distributed/write";
      distributed_interval = 10;
      schedule_splay_percent = 10;
      host_identifier = "specified";
      specified_identifier = config.networking.hostName;
    };
    packs =
      {
        inventory = "${packs}/inventory.conf";
        runtime = "${packs}/runtime.conf";
        compliance = "${packs}/compliance.conf";
      }
      // lib.optionalAttrs (cfg.hostTier == "server") {
        lab-extras = "${packs}/lab-extras.conf";
      };
  });
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    services.osquery = {
      enable = true;
      package = pkgs.osquery;
      flags = {
        config_path = "${configJson}";
        pidfile = "/var/run/osqueryd.pidfile";
        logger_path = builtins.dirOf cfg.logForwarding.lokiFile;
      };
    };

    # Persistence for node_key — survives impermanence reboots.
    environment.persistence."/persist" = lib.mkIf (config.nixfleet.persistence.enable or false) {
      files = [ cfg.nodeKeyPath ];
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/osquery 0750 osquery osquery -"
      "d ${builtins.dirOf cfg.logForwarding.lokiFile} 0750 osquery osquery -"
    ];

    # Daily compliance-evidence snapshot — integrates with nixfleet-compliance.
    systemd.services.nixfleet-osquery-evidence = {
      description = "osquery compliance evidence snapshot";
      after = [ "osqueryd.service" ];
      requires = [ "osqueryd.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.osquery}/bin/osqueryi --json --config_path ${packs}/compliance.conf -A schedule";
        StandardOutput = "file:/var/lib/nixfleet-compliance/osquery-evidence.json";
        StateDirectory = "nixfleet-compliance";
      };
    };
    systemd.timers.nixfleet-osquery-evidence = {
      description = "Daily osquery compliance evidence snapshot";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };
  };
}
