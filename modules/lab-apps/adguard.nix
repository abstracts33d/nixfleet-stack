# Per-machine opt-in: clients point DNS at lab's Tailscale IP.
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
      http.address = "127.0.0.1:3000"; # Caddy fronts
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
      # Flatten fleetHosts {ip = [names]} into [{domain, answer}].
      rewrites =
        let
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

  networking.firewall.allowedTCPPorts = [ 53 ];
  networking.firewall.allowedUDPPorts = [ 53 ];

  # DynamicUser stores state under /var/lib/private; both /var/lib/private and
  # the service subdir must be 0700.
  nixfleet.persistence.directories = [
    {
      directory = "/var/lib/private";
      mode = "0700";
    }
  ];
}
