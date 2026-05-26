# Clients configure sync_address in modules/core/_home/atuin.nix.
{
  config,
  lib,
  ...
}:
lib.mkIf config.fleet.server.enable {
  services.atuin = {
    enable = true;
    host = "127.0.0.1";
    port = 8888;
    openRegistration = true;
    database.createLocally = true;
  };

  nixfleet.persistence.directories = [
    {
      directory = "/var/lib/postgresql";
      user = "postgres";
      group = "postgres";
      mode = "0750";
    }
  ];
}
