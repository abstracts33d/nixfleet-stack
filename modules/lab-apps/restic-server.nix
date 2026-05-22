# Restic REST server — append-only backup target (server only).
# Clients push backups via https://restic.lab.internal.
# Server-side prune runs weekly to reclaim space (append-only clients can't prune).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  repoDir = "/var/lib/restic-fleet";
in
lib.mkIf config.fleet.server.enable {
  # REST server — append-only so compromised clients can't delete backups
  systemd.services.restic-rest-server = {
    description = "Restic REST server (append-only)";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.restic-rest-server}/bin/rest-server --path ${repoDir} --listen 127.0.0.1:8000 --append-only --no-auth";
      Restart = "on-failure";
      StateDirectory = "restic-fleet";
      DynamicUser = false;
      User = "root";
    };
  };

  # Initialize repo if it doesn't exist
  systemd.services.restic-repo-init = {
    description = "Initialize restic repository";
    after = [ "restic-rest-server.service" ];
    requires = [ "restic-rest-server.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    environment.RESTIC_REPOSITORY = "rest:http://127.0.0.1:8000/";
    environment.RESTIC_PASSWORD_FILE = config.age.secrets.restic-repo-password.path;
    path = [ pkgs.restic ];
    script = ''
      if ! restic snapshots &>/dev/null; then
        restic init
        echo "Restic repository initialized at ${repoDir}"
      else
        echo "Restic repository already exists"
      fi
    '';
  };

  # Server-side prune — append-only clients can't actually prune.
  # Run weekly to reclaim disk space.
  systemd.services.restic-server-prune = {
    description = "Restic server-side prune";
    serviceConfig.Type = "oneshot";
    environment.RESTIC_REPOSITORY = repoDir;
    environment.RESTIC_PASSWORD_FILE = config.age.secrets.restic-repo-password.path;
    path = [ pkgs.restic ];
    script = ''
      restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
    '';
  };

  systemd.timers.restic-server-prune = {
    description = "Weekly restic server-side prune";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 03:00";
      Persistent = true;
    };
  };

  nixfleet.persistence.directories = [
    {
      directory = repoDir;
      mode = "0700";
    }
  ];
}
