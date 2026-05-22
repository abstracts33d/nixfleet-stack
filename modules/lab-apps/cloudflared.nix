# Cloudflare Tunnel — outbound tunnel from lab to Cloudflare edge.
# No inbound ports needed. Tunnel routes external traffic to Caddy.
{
  config,
  lib,
  fleetServices,
  ...
}:
let
  services = fleetServices;
  publicDomain = "theabstractconnection.com";

  # Build ingress rules from services with external = true (subdomain only)
  externalServices = lib.filterAttrs (_: svc: svc.external && svc.subdomain != null) services;

  serviceIngress = lib.mapAttrs' (_name: svc: {
    name = "${svc.subdomain}.${publicDomain}";
    value = {
      service = "https://localhost:443";
      originRequest = {
        noTLSVerify = true;
        originServerName = "${svc.subdomain}.${publicDomain}";
      };
    };
  }) externalServices;

  # Root domain — static site (served by Caddy file_server)
  ingress = serviceIngress // {
    ${publicDomain} = {
      service = "https://localhost:443";
      originRequest = {
        noTLSVerify = true;
        originServerName = publicDomain;
      };
    };
  };
in
lib.mkIf config.fleet.server.enable {
  services.cloudflared = {
    enable = true;
    tunnels."lab" = {
      credentialsFile = config.age.secrets."cloudflared-tunnel-credentials".path;
      default = "http_status:404";
      inherit ingress;
    };
  };

  # Ensure cloudflared user exists for secret ownership
  users.users.cloudflared = {
    isSystemUser = true;
    group = "cloudflared";
  };
  users.groups.cloudflared = { };

  nixfleet.persistence.directories = [
    {
      directory = "/var/lib/cloudflared";
      user = "cloudflared";
      group = "cloudflared";
      mode = "0700";
    }
  ];
}
