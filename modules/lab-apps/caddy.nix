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
  apexSite = pkgs.writeTextDir "index.html" ''
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width,initial-scale=1">
      <title>the abstract connection</title>
      <style>
        html,body{margin:0;height:100%;background:#000;color:#fff;
          font-family:system-ui,-apple-system,sans-serif}
        body{display:flex;align-items:center;justify-content:center}
        h1{font-weight:300;letter-spacing:0.15em;
           font-size:clamp(1.2rem,4vw,2.5rem);margin:0}
      </style>
    </head>
    <body><h1>the abstract connection</h1></body>
    </html>
  '';

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
    ${publicDomain} = {
      extraConfig = ''
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
        }
        root * ${apexSite}
        file_server
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
  ];
}
