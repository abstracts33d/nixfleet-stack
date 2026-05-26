# fleet-dm — osquery fleet manager server. Lab-only.
#
# Dedicated MariaDB + Redis (separate ports/data dirs from any other lab
# services), Caddy vhost with internal TLS at <domain>, tailnet-only by
# consumer policy (consumer marks external=false in services.nix).
#
# fleet-dm is MySQL-only (no Postgres support upstream — server/datastore/mysql
# is the sole datastore). MariaDB 10.5+ speaks the same wire protocol and
# satisfies the Go driver, so we run a dedicated mariadbd instance bound to
# 127.0.0.1 with skip-grant-tables-style trust auth — fleet-dm is the only
# client, surface is localhost, the password adds no real security.
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
        description = "Dedicated MariaDB port. Default 3307 leaves 3306 free for any shared lab MySQL.";
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
    # Dedicated MariaDB for fleet-dm. Custom systemd unit (not services.mysql
    # which expects a single instance) so we can pin port/datadir/socket and
    # keep this isolated from any future shared lab MySQL.
    systemd.services.fleet-dm-mysql = {
      description = "MariaDB (dedicated for fleet-dm)";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "fleet-dm-mysql";
        Group = "fleet-dm-mysql";
        StateDirectory = "fleet-dm-mysql";
        StateDirectoryMode = "0700";
        # First boot: mariadb-install-db lays down the system tables, then
        # ExecStartPost creates the fleet user + database (idempotent: marker
        # file gates the bootstrap).
        ExecStartPre = pkgs.writeShellScript "fleet-dm-mysql-install" ''
          set -eu
          if [ ! -d ${cfg.mysql.dataDir}/mysql ]; then
            ${pkgs.mariadb}/bin/mariadb-install-db \
              --datadir=${cfg.mysql.dataDir} \
              --user=fleet-dm-mysql \
              --auth-root-authentication-method=normal \
              --skip-test-db
          fi
        '';
        ExecStart = ''
          ${pkgs.mariadb}/bin/mariadbd \
            --datadir=${cfg.mysql.dataDir} \
            --bind-address=127.0.0.1 \
            --port=${toString cfg.mysql.port} \
            --socket=/run/fleet-dm-mysql/mysqld.sock \
            --pid-file=/run/fleet-dm-mysql/mysqld.pid \
            --user=fleet-dm-mysql
        '';
        # Bootstrap the database + user once. Idempotent: CREATE IF NOT EXISTS.
        # Runs after mariadbd is accepting connections — small sleep is the
        # pragmatic choice over mysqladmin ping in a loop.
        ExecStartPost = pkgs.writeShellScript "fleet-dm-mysql-bootstrap" ''
          set -eu
          for i in $(seq 1 30); do
            if ${pkgs.mariadb}/bin/mariadb \
                --socket=/run/fleet-dm-mysql/mysqld.sock \
                --user=root \
                -e "SELECT 1" >/dev/null 2>&1; then
              break
            fi
            sleep 1
          done
          ${pkgs.mariadb}/bin/mariadb \
            --socket=/run/fleet-dm-mysql/mysqld.sock \
            --user=root <<'SQL'
CREATE DATABASE IF NOT EXISTS ${cfg.mysql.database}
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${cfg.mysql.user}'@'127.0.0.1' IDENTIFIED BY '';
CREATE USER IF NOT EXISTS '${cfg.mysql.user}'@'localhost' IDENTIFIED BY '';
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
        ExecStart = ''
          ${cfg.package}/bin/fleet serve \
            --mysql_address=127.0.0.1:${toString cfg.mysql.port} \
            --mysql_username=${cfg.mysql.user} \
            --mysql_database=${cfg.mysql.database} \
            --redis_address=127.0.0.1:${toString cfg.redis.port} \
            --server_address=127.0.0.1:${toString cfg.port} \
            --server_tls=false
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

    # Caddy vhost — internal TLS, tailnet-only (external=false in consumer).
    services.caddy.virtualHosts.${cfg.domain}.extraConfig = ''
      tls internal
      reverse_proxy 127.0.0.1:${toString cfg.port}
    '';

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
