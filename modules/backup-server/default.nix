# Backup-server scope — Restic REST server.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixfleet.backupServer;

  restArgs = lib.concatStringsSep " " (
    [
      "--path ${cfg.dataDir}"
      "--listen ${cfg.listenAddress}"
    ]
    ++ lib.optional cfg.appendOnly "--append-only"
    ++ lib.optional (cfg.authFile == null) "--no-auth"
    ++ lib.optional (cfg.authFile != null) "--htpasswd-file=${cfg.authFile}"
    ++ lib.optionals (cfg.tls.certFile != null && cfg.tls.keyFile != null) [
      "--tls"
      "--tls-cert=${cfg.tls.certFile}"
      "--tls-key=${cfg.tls.keyFile}"
    ]
  );
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        systemd.services.restic-rest-server = {
          description = "Restic REST server";
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            ExecStart = "${pkgs.restic-rest-server}/bin/rest-server ${restArgs}";
            Restart = "on-failure";
            StateDirectory = baseNameOf cfg.dataDir;
            DynamicUser = false;
            User = "root";
          };
        };

        nixfleet.persistence.directories = [ cfg.dataDir ];
      }

      (lib.mkIf cfg.prune.enable {
        assertions = [
          {
            assertion = cfg.prune.passwordFile != null;
            message = "nixfleet.backupServer.prune.enable requires prune.passwordFile.";
          }
        ];

        systemd.timers.nixfleet-backup-server-prune = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = cfg.prune.schedule;
            Persistent = true;
            RandomizedDelaySec = "1h";
          };
        };

        systemd.services.nixfleet-backup-server-prune = {
          description = "Restic repository prune (server-side)";
          after = [ "restic-rest-server.service" ];
          serviceConfig = {
            Type = "oneshot";
          };
          environment = {
            RESTIC_REPOSITORY = cfg.dataDir;
            RESTIC_PASSWORD_FILE = cfg.prune.passwordFile;
          };
          path = [ pkgs.restic ];
          script = ''
            restic forget \
              --keep-daily ${toString cfg.prune.keep.daily} \
              --keep-weekly ${toString cfg.prune.keep.weekly} \
              --keep-monthly ${toString cfg.prune.keep.monthly} \
              --prune
          '';
        };
      })
    ]
  );
}
