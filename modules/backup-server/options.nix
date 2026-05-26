{ lib, ... }:
let
  inherit (lib) types;
in
{
  options.nixfleet.backupServer = {
    enable = lib.mkEnableOption "Restic REST server (append-only by default)";

    domain = lib.mkOption {
      type = types.str;
      example = "restic.lab.internal";
      description = "Public domain (informational; reverse-proxy wiring is the consumer's job).";
    };

    listenAddress = lib.mkOption {
      type = types.str;
      default = "127.0.0.1:8000";
      description = "Bind address:port for the REST server.";
    };

    dataDir = lib.mkOption {
      type = types.str;
      default = "/var/lib/restic-fleet";
      description = "Filesystem root for backup repositories.";
    };

    appendOnly = lib.mkOption {
      type = types.bool;
      default = true;
      description = "Run the server in append-only mode (clients cannot delete). Pruning is a local maintenance job.";
    };

    authFile = lib.mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "htpasswd file for REST auth. Null = no auth (intended for loopback-only deployments).";
    };

    tls = {
      certFile = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "TLS cert file. Null disables TLS (plain HTTP).";
      };
      keyFile = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "TLS key file. Null disables TLS.";
      };
    };

    prune = {
      enable = lib.mkOption {
        type = types.bool;
        default = true;
        description = "Run a local restic prune timer (server-side, since append-only clients cannot prune).";
      };
      schedule = lib.mkOption {
        type = types.str;
        default = "weekly";
        description = "systemd OnCalendar expression for the prune job.";
      };
      keep = {
        daily = lib.mkOption {
          type = types.int;
          default = 7;
        };
        weekly = lib.mkOption {
          type = types.int;
          default = 4;
        };
        monthly = lib.mkOption {
          type = types.int;
          default = 6;
        };
      };
      passwordFile = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Restic repo password. Required when prune.enable is true.";
      };
    };
  };
}
