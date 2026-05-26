# osquery agent — nix-darwin variant. nix-darwin has no services.osquery
# wrapper, so we drive osqueryd directly via launchd.
#
# TCC NOTE: first activation on a Darwin host requires the operator to grant
# osquery the appropriate permissions in System Settings → Privacy & Security.
# Until that's done, several tables (file_events on /etc, fs metadata on
# protected paths) will silently return empty result sets.
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
  '';

  # Plugin-loading + TLS flags must be passed as CLI args, not via JSON config.
  # osquery silently ignores them inside the config file (plugin selection
  # happens before the config is parsed). See NixOS variant for the same fix.
  tlsHostname = lib.removePrefix "https://" (lib.removePrefix "http://" cfg.fleetDmUrl);
  osqueryFlagfile = pkgs.writeText "osquery.flags" ''
    --tls_hostname=${tlsHostname}
    --enroll_secret_path=${toString cfg.enrollSecretFile}
    --enroll_tls_endpoint=/api/v1/osquery/enroll
    --config_plugin=tls
    --config_tls_endpoint=/api/v1/osquery/config
    --config_tls_refresh=60
    --logger_plugin=tls,filesystem
    --logger_tls_endpoint=/api/v1/osquery/log
    --logger_tls_period=10
    --logger_path=${builtins.dirOf cfg.logForwarding.lokiFile}
    --disable_distributed=false
    --distributed_plugin=tls
    --distributed_tls_read_endpoint=/api/v1/osquery/distributed/read
    --distributed_tls_write_endpoint=/api/v1/osquery/distributed/write
    --distributed_interval=10
    --host_identifier=specified
    --specified_identifier=${config.networking.hostName}
  '';

  osqueryConf = pkgs.writeText "osquery.conf" (builtins.toJSON {
    options = {
      schedule_splay_percent = 10;
    };
    packs = {
      inventory = "${packs}/inventory.conf";
      runtime = "${packs}/runtime.conf";
      compliance = "${packs}/compliance.conf";
    };
  });
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    launchd.daemons.osqueryd = {
      script = ''
        mkdir -p ${builtins.dirOf cfg.logForwarding.lokiFile}
        exec ${pkgs.osquery}/bin/osqueryd \
          --flagfile ${osqueryFlagfile} \
          --config_path ${osqueryConf} \
          --pidfile /var/run/osqueryd.pidfile
      '';
      serviceConfig = {
        Label = "io.osquery.agent";
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/var/log/osquery/stdout.log";
        StandardErrorPath = "/var/log/osquery/stderr.log";
      };
    };
  };
}
