# Jellyfin media server — streams to TVs, phones, browsers (server only).
# Libraries configured via web UI on first launch (see docs/manual-setup.md).
{
  config,
  lib,
  ...
}:
let
  cfg = config.fleet.jellyfin;
in
{
  options.fleet.jellyfin.enable = lib.mkOption {
    type = lib.types.bool;
    default = config.fleet.server.enable;
    description = "Enable Jellyfin media server. Defaults to true on servers.";
  };

  config = lib.mkIf cfg.enable {
    services.jellyfin = {
      enable = true;
      openFirewall = true;
    };

    # Mount media drive (ext4, labeled "media") for Jellyfin + Samba
    fileSystems."/srv/media" = {
      device = "/dev/disk/by-label/media";
      fsType = "ext4";
      options = [
        "nofail"
        "x-systemd.device-timeout=5"
      ];
    };

    users.users.jellyfin.extraGroups = [ "nogroup" ];

    nixfleet.persistence.directories = [
      {
        directory = "/var/lib/jellyfin";
        user = "jellyfin";
        group = "jellyfin";
        mode = "0700";
      }
    ];
  };
}
