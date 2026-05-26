# Documents: authenticated (primary operator). Media: guest read-only.
{
  config,
  lib,
  ...
}:
let
  shareRoot = "/persist/srv/share";
in
lib.mkIf config.fleet.server.enable {
  services.samba = {
    enable = true;
    nmbd.enable = false; # crashes on Samba 4.22, redundant with WSDD + Avahi
    openFirewall = true;
    settings = {
      global = {
        "server string" = "lab";
        "map to guest" = "Bad User";
        "guest account" = "nobody";
        "security" = "user";
      };
      documents = {
        path = "${shareRoot}/documents";
        "read only" = "no";
        "guest ok" = "no";
        "valid users" = config.nixfleet.operators._primaryName;
        "create mask" = "0664";
        "directory mask" = "0775";
        "force user" = "nobody";
        "force group" = "nogroup";
      };
      media = {
        path = "/srv/media";
        "read only" = "yes";
        "guest ok" = "yes";
      };
    };
  };

  # smbpasswd needs the password piped twice (new + confirm).
  systemd.services.samba-user-setup = {
    description = "Set up Samba user from agenix secret";
    after = [
      "agenix.service"
      "samba-smbd.service"
    ];
    requires = [ "samba-smbd.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ config.services.samba.package ];
    script = ''
      PASSWORD=$(cat ${config.age.secrets."samba-password".path})
      printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" | smbpasswd -a -s ${config.nixfleet.operators._primaryName}
    '';
  };

  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      userServices = true;
    };
  };

  systemd.tmpfiles.rules = [
    "d ${shareRoot}/documents 0775 nobody nogroup -"
  ];

  nixfleet.persistence.directories = [
    {
      directory = "/var/lib/samba";
      mode = "0700";
    }
  ];
}
