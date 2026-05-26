# Initial setup via web UI; phones auto-upload.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.fleet.immich;
in
{
  options.fleet.immich.enable = lib.mkOption {
    type = lib.types.bool;
    default = config.fleet.server.enable;
    description = "Enable Immich photo management. Defaults to true on servers.";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.immich-cli
      pkgs.immich-go # Google Takeout import (handles JSON metadata)
    ];

    services.immich = {
      enable = true;
      openFirewall = true;
      host = "0.0.0.0";
      mediaLocation = "/srv/media/immich";
      machine-learning.enable = true;
    };

    systemd.tmpfiles.rules = [
      "d /srv/media/immich 0700 immich immich -"
    ];

    nixfleet.persistence.directories = [
      {
        directory = "/var/lib/immich";
        user = "immich";
        group = "immich";
        mode = "0700";
      }
    ];
  };
}
