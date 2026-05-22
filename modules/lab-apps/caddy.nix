# Caddy — reverse proxy for lab services (server only).
# Dual-domain:
#   - *.lab.internal: internal TLS (Caddy CA) for fleet/Tailscale access
#   - *.theabstractconnection.com: Let's Encrypt wildcard (DNS-01) for LAN + external
# NixFleet CP stays on its own mTLS port, not proxied.
{
  config,
  lib,
  pkgs,
  fleetServices,
  ...
}:
let
  services = fleetServices;
  internalDomain = "lab.internal";
  publicDomain = "theabstractconnection.com";
  # Temporary preview of arcanesys-website (pair-review). Vendored
  # pre-built Astro output — revert this directory + the root vhost
  # below once the upstream pitch site goes live.
  previewSite = ./arcanesys-website-preview;

  # Internal vhosts (all services, internal TLS)
  mkInternalVhost = _name: svc: {
    name = if svc.subdomain != null then "${svc.subdomain}.${internalDomain}" else internalDomain;
    value = {
      extraConfig = ''
        tls internal
        reverse_proxy localhost:${toString svc.port}
      '';
    };
  };

  # Public vhosts (external services with a subdomain, ACME via Cloudflare DNS-01)
  externalServices = lib.filterAttrs (_: svc: svc.external && svc.subdomain != null) services;

  mkPublicVhost = _name: svc: {
    name = "${svc.subdomain}.${publicDomain}";
    value = {
      extraConfig = ''
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
        }
        reverse_proxy localhost:${toString svc.port}
      '';
    };
  };

  internalVhosts = builtins.listToAttrs (lib.mapAttrsToList mkInternalVhost services);
  publicVhosts = builtins.listToAttrs (lib.mapAttrsToList mkPublicVhost externalServices) // {
    # Root domain — static site (technomancer-dream) at /, with the
    # vendored arcanesys-website preview mounted under /nixfleet.
    # Both the directory and this handle_path block are temporary —
    # remove them when the upstream pitch site (arcanesys.fr) is the
    # canonical home.
    ${publicDomain} = {
      extraConfig = ''
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
        }
        redir /nixfleet /nixfleet/ permanent
        handle_path /nixfleet/* {
          root * ${previewSite}
          file_server
          encode gzip
        }
        handle {
          root * /var/lib/technomancer-dream
          file_server
        }
      '';
    };
  };
in
lib.mkIf config.fleet.server.enable {
  services.caddy = {
    enable = true;
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
      hash = "sha256-Olz4W84Kiyldy+JtbIicVCL7dAYl4zq+2rxEOUTObxA=";
    };
    globalConfig = ''
      servers {
        metrics
      }
    '';
    virtualHosts = internalVhosts // publicVhosts;
  };

  # Inject Cloudflare API token from agenix secret into Caddy's environment.
  # The secret file contains only the token value (no KEY=VALUE format),
  # so we use a wrapper script to export it as an env var.
  systemd.services.caddy.serviceConfig.ExecStartPre = [
    "+${pkgs.writeShellScript "caddy-cloudflare-env" ''
      TOKEN=$(cat ${config.age.secrets."cloudflare-api-token".path})
      echo "CLOUDFLARE_API_TOKEN=$TOKEN" > /run/caddy-env
      chown caddy:caddy /run/caddy-env
      chmod 600 /run/caddy-env
    ''}"
  ];
  systemd.services.caddy.serviceConfig.EnvironmentFile = "-/run/caddy-env";

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  nixfleet.persistence.directories = [
    {
      directory = "/var/lib/caddy";
      user = "caddy";
      group = "caddy";
      mode = "0700";
    }
    {
      directory = "/var/lib/technomancer-dream";
      mode = "0755";
    }
  ];
}
