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

  osqueryConf = pkgs.writeText "osquery.conf" (builtins.toJSON {
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
      host_identifier = "specified";
      specified_identifier = config.networking.hostName;
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
