# Tailnet-only behind Caddy at https://ntfy.lab.internal.
# auth-default-access=read-write is intentional: tailnet is the auth boundary.
{
  config,
  lib,
  fleetServices,
  ...
}:
let
  inherit (fleetServices.ntfy) port;
in
lib.mkIf config.fleet.server.enable {
  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://ntfy.lab.internal";
      listen-http = "127.0.0.1:${toString port}";
      behind-proxy = true;
      auth-default-access = "read-write";
      cache-duration = "12h";
    };
  };

  nixfleet.persistence.directories = [
    {
      directory = "/var/lib/private/ntfy-sh";
      user = "root";
      group = "root";
      mode = "0700";
    }
  ];
}
