# ntfy — push-notification target for Alertmanager (server only).
# Tailnet-only via caddy at https://ntfy.lab.internal; Alertmanager
# POSTs to the `nixfleet-alerts` topic over plain localhost HTTP.
# `auth-default-access = "read-write"` is intentional: lab is
# Tailnet-firewalled; auth would require agenix-managed credentials
# we don't have yet.
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
      # Conservative retention — most alerts resolve in minutes.
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
