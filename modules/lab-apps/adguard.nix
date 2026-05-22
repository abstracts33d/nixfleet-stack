# AdGuard Home — DNS ad-blocking + web UI (server only).
# Per-machine opt-in: clients point their DNS to lab's Tailscale IP.
{
  config,
  lib,
  fleetHosts,
  ...
}:
lib.mkIf config.fleet.server.enable {
  services.adguardhome = {
    enable = true;
    settings = {
      http.address = "127.0.0.1:3000"; # web UI behind Caddy
      dns = {
        bind_hosts = [ "0.0.0.0" ];
        port = 53;
        upstream_dns = [
          "1.1.1.1"
          "9.9.9.9"
          "8.8.8.8"
        ];
        bootstrap_dns = [
          "1.1.1.1"
          "9.9.9.9"
        ];
      };
      # Fleet hostname → Tailscale IP rewrites
      rewrites =
        let
          # Flatten {ip = [names]} into [{domain, answer}]
          entries = builtins.concatLists (
            builtins.attrValues (
              builtins.mapAttrs (
                ip: names:
                map (name: {
                  domain = name;
                  answer = ip;
                }) names
              ) fleetHosts
            )
          );
        in
        entries;

      filtering = {
        protection_enabled = true;
        filtering_enabled = true;
      };
      filters = [
        {
          enabled = true;
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
          name = "AdGuard DNS filter";
          id = 1;
        }
        {
          enabled = true;
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt";
          name = "AdAway Default Blocklist";
          id = 2;
        }
      ];
    };
  };

  # DNS port (web UI is localhost-only, accessed via Caddy)
  networking.firewall.allowedTCPPorts = [ 53 ];
  networking.firewall.allowedUDPPorts = [ 53 ];

  # AdGuard Home runs under DynamicUser — its state lives in /var/lib/private/.
  # Both /var/lib/private and the subdirectory need 0700 for DynamicUser services.
  nixfleet.persistence.directories = [
    {
      directory = "/var/lib/private";
      mode = "0700";
    }
  ];
}
