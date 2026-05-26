# fleet-dm — osquery fleet manager server. Lab-only.
#
# Dedicated Postgres + Redis (separate ports/data dirs from any other lab
# services), Caddy vhost with internal TLS at <domain>, tailnet-only by
# consumer policy (consumer marks external=false in services.nix).
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

    postgres = {
      port = lib.mkOption {
        type = lib.types.port;
        default = 5433;
      };
      dataDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/fleet-dm-postgres";
      };
      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Optional path to a file containing the fleet-dm Postgres password.
          When null (default), postgres runs with trust auth on 127.0.0.1 only —
          fleet-dm is the only client and the surface is localhost-bound, so the
          password adds no real security. Provide a path if you want md5 auth
          (e.g. when sharing the dedicated instance with another local client).
        '';
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
    # Dedicated Postgres for fleet-dm — separate from any shared lab Postgres.
    systemd.services.fleet-dm-postgres = {
      description = "PostgreSQL (dedicated for fleet-dm)";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "notify";
        User = "fleet-dm-postgres";
        Group = "fleet-dm-postgres";
        StateDirectory = "fleet-dm-postgres";
        StateDirectoryMode = "0700";
        # initdb on first boot, then run the daemon. PG_VERSION is postgres'
        # canonical "data dir initialized" marker.
        # Auth: trust for both host and local — postgres is bound to 127.0.0.1
        # only and the fleet-dm service is the only legitimate client. No
        # external attack surface ⇒ password adds no real security here.
        ExecStartPre = pkgs.writeShellScript "fleet-dm-postgres-initdb" ''
          set -eu
          if [ ! -f ${cfg.postgres.dataDir}/PG_VERSION ]; then
            ${pkgs.postgresql_16}/bin/initdb -D ${cfg.postgres.dataDir} \
              --auth-host=trust --auth-local=trust \
              --encoding=UTF8 --locale=C \
              --username=fleet
            cat >> ${cfg.postgres.dataDir}/postgresql.conf <<'EOF'

# Managed by nixfleet-stack/modules/lab-apps/fleet-dm.nix.
unix_socket_directories = '/tmp'
listen_addresses = '127.0.0.1'
EOF
          fi
        '';
        ExecStart = ''
          ${pkgs.postgresql_16}/bin/postgres \
            -D ${cfg.postgres.dataDir} \
            -p ${toString cfg.postgres.port} \
            -k /tmp
        '';
      };
    };
    users.users.fleet-dm-postgres = {
      isSystemUser = true;
      group = "fleet-dm-postgres";
      home = cfg.postgres.dataDir;
    };
    users.groups.fleet-dm-postgres = { };

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
        "fleet-dm-postgres.service"
        "fleet-dm-redis.service"
      ];
      requires = [
        "fleet-dm-postgres.service"
        "fleet-dm-redis.service"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = "fleet-dm";
        Group = "fleet-dm";
        StateDirectory = "fleet-dm";
        EnvironmentFile = lib.mkIf (cfg.postgres.passwordFile != null) cfg.postgres.passwordFile;
        ExecStart = ''
          ${cfg.package}/bin/fleet serve \
            --mysql_address=127.0.0.1:${toString cfg.postgres.port} \
            --mysql_username=fleet \
            --mysql_database=fleet \
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
              directory = cfg.postgres.dataDir;
              user = "fleet-dm-postgres";
              group = "fleet-dm-postgres";
              mode = "0750";
            }
            "/var/lib/fleet-dm"
          ];
        };

    networking.firewall.allowedTCPPorts = lib.mkAfter [ cfg.port ];
  };
}
