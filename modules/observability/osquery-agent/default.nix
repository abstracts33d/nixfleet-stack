# osquery agent — NixOS variant. Wraps services.osquery with tier-B allowlist
# packs and dual logging (TLS to fleet-dm + filesystem to Vector → Loki).
#
# Compliance-evidence snapshots (the local osquery-evidence.json) are the
# job of `compliance.evidence.osquery` in nixfleet-compliance (commit
# f647506 on dev). This module no longer carries its own oneshot/timer —
# operators that want the per-host snapshot enable the producer in their
# consumer config:
#
#   compliance.evidence.osquery.enable = true;
#
# The two compose: this module runs the daemon (osqueryd) + enrolls with
# fleet-dm; the compliance producer runs osqueryi -A schedule once per
# activation and writes the file the operator-side CLI fetches.
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

  # Plugin-loading + TLS connection flags MUST be CLI flags (--flagfile).
  # osquery silently ignores these when set inside the JSON config file —
  # the plugins they select are loaded before the config is read.
  # services.osquery.flags renders them as CLI args to osqueryd.
  #
  # `logger_path`, `database_path`, `pidfile` are upstream read-only
  # (pinned to /var/log/osquery, /var/lib/osquery/osquery.db, /run/osquery/*).
  # Do not declare them here — assertion failure on multiple definitions.
  tlsFlags = {
    tls_hostname = lib.removePrefix "https://" (lib.removePrefix "http://" cfg.fleetDmUrl);
    # osquery doesn't consult the system trust store by default — it looks
    # at its own hardcoded /opt/osquery/share/osquery/certs/certs.pem path
    # (an upstream Linux-package assumption that doesn't exist on NixOS).
    # Point it at the NixOS system bundle so it picks up whatever the
    # operator anchored via security.pki.certificateFiles (typically the
    # local Caddy CA for tls internal vhosts).
    tls_server_certs = "/etc/ssl/certs/ca-certificates.crt";
    enroll_secret_path = toString cfg.enrollSecretFile;
    enroll_tls_endpoint = "/api/v1/osquery/enroll";
    config_plugin = "tls";
    config_tls_endpoint = "/api/v1/osquery/config";
    config_tls_refresh = "60";
    logger_plugin = "tls,filesystem";
    logger_tls_endpoint = "/api/v1/osquery/log";
    logger_tls_period = "10";
    disable_distributed = "false";
    distributed_plugin = "tls";
    distributed_tls_read_endpoint = "/api/v1/osquery/distributed/read";
    distributed_tls_write_endpoint = "/api/v1/osquery/distributed/write";
    distributed_interval = "10";
    host_identifier = "specified";
    specified_identifier = config.networking.hostName;
  };

  # Runtime-only options (osqueryd reads from config file): pack registration
  # + global tunables that don't gate plugin loading.
  configJson = pkgs.writeText "osquery.conf" (builtins.toJSON {
    options = {
      schedule_splay_percent = 10;
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
      flags = tlsFlags // {
        config_path = "${configJson}";
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
  };
}
