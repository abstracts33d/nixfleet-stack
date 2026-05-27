# fleet-dm — osquery fleet manager server. Lab-only.
#
# Dedicated MySQL 8 + Redis (separate ports/data dirs from any other lab
# services), Caddy vhost with internal TLS at <domain>, tailnet-only by
# consumer policy (consumer marks external=false in services.nix).
#
# fleet-dm officially supports MySQL 8.x only — MariaDB rejected one of the
# packaged schema migrations (TIMESTAMP(6)+CURRENT_TIMESTAMP MODIFY COLUMN
# syntax MariaDB parses differently). Bound to 127.0.0.1 with empty-password
# trust auth — fleet-dm is the only client, surface is localhost, the
# password adds no real security at the loopback boundary.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixfleet.fleet-dm;
in
{
  options.nixfleet.fleet-dm = {
    enable = lib.mkEnableOption "fleet-dm server (lab-app)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8412;
      description = "HTTP port for fleet-dm. Caddy fronts this.";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "fleet.lab.internal";
      description = "FQDN for fleet-dm UI.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.fleet;
      defaultText = lib.literalExpression "pkgs.fleet";
      description = "fleet-dm package. Pin in consumer if schema churn requires it.";
    };

    mysql = {
      port = lib.mkOption {
        type = lib.types.port;
        default = 3307;
        description = "Dedicated MySQL 8 port. Default 3307 leaves 3306 free for any future shared lab MySQL.";
      };
      dataDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/fleet-dm-mysql";
      };
      database = lib.mkOption {
        type = lib.types.str;
        default = "fleet";
      };
      user = lib.mkOption {
        type = lib.types.str;
        default = "fleet";
      };
    };

    redis.port = lib.mkOption {
      type = lib.types.port;
      default = 6380;
    };

    enrollSecretFile = lib.mkOption {
      type = lib.types.str;
      description = "Path to a file containing the fleet-dm enrollment secret (UUID).";
    };
  };

  config = lib.mkIf cfg.enable {
    # Dedicated MySQL 8 for fleet-dm. Custom systemd unit (not services.mysql
    # which expects a single instance) so we can pin port/datadir/socket and
    # keep this isolated from any future shared lab MySQL.
    systemd.services.fleet-dm-mysql = {
      description = "MySQL 8 (dedicated for fleet-dm)";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "fleet-dm-mysql";
        Group = "fleet-dm-mysql";
        StateDirectory = "fleet-dm-mysql";
        StateDirectoryMode = "0700";
        # First boot: mysqld --initialize-insecure lays down the system schema
        # with a passwordless root (safe on a 127.0.0.1-only socket).
        # ExecStartPost then creates the fleet user + database.
        #
        # Migration guard: an earlier revision of this module initialized the
        # data dir as MariaDB. MySQL 8 refuses to start on a MariaDB layout
        # (different system tables + InnoDB metadata), so we detect the
        # MariaDB-specific aria_log_control file and wipe before re-init.
        # Safe because fleet's schema migrations never completed under
        # MariaDB — there's no real data on disk.
        ExecStartPre = pkgs.writeShellScript "fleet-dm-mysql-install" ''
          set -eu
          if [ -f ${cfg.mysql.dataDir}/aria_log_control ]; then
            echo "fleet-dm-mysql: detected MariaDB layout; wiping (no fleet data ever landed)" >&2
            ${pkgs.findutils}/bin/find ${cfg.mysql.dataDir} -mindepth 1 -delete
          fi
          if [ ! -d ${cfg.mysql.dataDir}/mysql ]; then
            ${pkgs.mysql80}/bin/mysqld \
              --initialize-insecure \
              --datadir=${cfg.mysql.dataDir} \
              --user=fleet-dm-mysql
          fi
        '';
        ExecStart = ''
          ${pkgs.mysql80}/bin/mysqld \
            --datadir=${cfg.mysql.dataDir} \
            --bind-address=127.0.0.1 \
            --port=${toString cfg.mysql.port} \
            --socket=/run/fleet-dm-mysql/mysqld.sock \
            --pid-file=/run/fleet-dm-mysql/mysqld.pid \
            --mysqlx=OFF \
            --user=fleet-dm-mysql
        '';
        # Bootstrap the database + user. Idempotent: CREATE IF NOT EXISTS.
        # Poll the socket until mysqld accepts connections (typically <5s).
        ExecStartPost = pkgs.writeShellScript "fleet-dm-mysql-bootstrap" ''
          set -eu
          for i in $(seq 1 30); do
            if ${pkgs.mysql80}/bin/mysql \
                --socket=/run/fleet-dm-mysql/mysqld.sock \
                --user=root \
                -e "SELECT 1" >/dev/null 2>&1; then
              break
            fi
            sleep 1
          done
          ${pkgs.mysql80}/bin/mysql \
            --socket=/run/fleet-dm-mysql/mysqld.sock \
            --user=root <<'SQL'
CREATE DATABASE IF NOT EXISTS ${cfg.mysql.database}
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${cfg.mysql.user}'@'127.0.0.1';
CREATE USER IF NOT EXISTS '${cfg.mysql.user}'@'localhost';
GRANT ALL PRIVILEGES ON ${cfg.mysql.database}.* TO '${cfg.mysql.user}'@'127.0.0.1';
GRANT ALL PRIVILEGES ON ${cfg.mysql.database}.* TO '${cfg.mysql.user}'@'localhost';
FLUSH PRIVILEGES;
SQL
        '';
        RuntimeDirectory = "fleet-dm-mysql";
        RuntimeDirectoryMode = "0750";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
    users.users.fleet-dm-mysql = {
      isSystemUser = true;
      group = "fleet-dm-mysql";
      home = cfg.mysql.dataDir;
    };
    users.groups.fleet-dm-mysql = { };

    # Dedicated Redis — cache-only, no persistence.
    systemd.services.fleet-dm-redis = {
      description = "Redis (dedicated for fleet-dm)";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = "fleet-dm-redis";
        Group = "fleet-dm-redis";
        StateDirectory = "fleet-dm-redis";
        ExecStart = ''
          ${pkgs.redis}/bin/redis-server \
            --bind 127.0.0.1 \
            --port ${toString cfg.redis.port} \
            --appendonly no \
            --save "" \
            --dir /var/lib/fleet-dm-redis
        '';
      };
    };
    users.users.fleet-dm-redis = {
      isSystemUser = true;
      group = "fleet-dm-redis";
      home = "/var/lib/fleet-dm-redis";
    };
    users.groups.fleet-dm-redis = { };

    # fleet-dm server.
    systemd.services.fleet-dm = {
      description = "fleet-dm (osquery fleet manager)";
      after = [
        "fleet-dm-mysql.service"
        "fleet-dm-redis.service"
      ];
      requires = [
        "fleet-dm-mysql.service"
        "fleet-dm-redis.service"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = "fleet-dm";
        Group = "fleet-dm";
        StateDirectory = "fleet-dm";
        # fleet schema migrations — idempotent, fast no-op when up to date.
        # Must run on every start so version bumps pick up new migrations
        # without operator intervention.
        ExecStartPre = ''
          ${cfg.package}/bin/fleet prepare db \
            --mysql_address=127.0.0.1:${toString cfg.mysql.port} \
            --mysql_username=${cfg.mysql.user} \
            --mysql_database=${cfg.mysql.database} \
            --no-prompt
        '';
        # --osquery_enroll_secret_path seeds the global enroll secret into
        # the database at startup. Without it fleet-dm rejects every
        # enrollment with "No node key returned from TLS enroll plugin"
        # because no secret exists in the enroll_secrets table for fleet
        # to match against. Idempotent: fleet-dm upserts on each start.
        ExecStart = ''
          ${cfg.package}/bin/fleet serve \
            --mysql_address=127.0.0.1:${toString cfg.mysql.port} \
            --mysql_username=${cfg.mysql.user} \
            --mysql_database=${cfg.mysql.database} \
            --redis_address=127.0.0.1:${toString cfg.redis.port} \
            --server_address=127.0.0.1:${toString cfg.port} \
            --server_tls=false \
            --osquery_enroll_secret_path=${cfg.enrollSecretFile}
        '';
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
    users.users.fleet-dm = {
      isSystemUser = true;
      group = "fleet-dm";
      home = "/var/lib/fleet-dm";
    };
    users.groups.fleet-dm = { };

    # Caddy vhost is auto-built by lab-apps/caddy.nix from the consumer's
    # _data/services.nix entry (subdomain="fleet", external=false → tailnet
    # only). Declaring it here too caused a multi-definition merge on
    # `extraConfig` (lib.types.lines concatenates), producing an invalid
    # Caddyfile with duplicated `tls`/`reverse_proxy` directives — Caddy
    # silently kept the old config across activations because reloads
    # failed parse.

    # Persistence (impermanence) for state dirs.
    environment.persistence."/persist" =
      lib.mkIf (config ? nixfleet && config.nixfleet ? persistence && config.nixfleet.persistence.enable)
        {
          directories = [
            {
              directory = cfg.mysql.dataDir;
              user = "fleet-dm-mysql";
              group = "fleet-dm-mysql";
              mode = "0700";
            }
            "/var/lib/fleet-dm"
          ];
        };

    networking.firewall.allowedTCPPorts = lib.mkAfter [ cfg.port ];
  };
}
