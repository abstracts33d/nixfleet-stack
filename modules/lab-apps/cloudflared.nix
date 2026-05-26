# Outbound tunnel to Cloudflare edge → Caddy. No inbound ports needed.
{
  config,
  lib,
  fleetServices,
  ...
}:
let
  services = fleetServices;
  publicDomain = "theabstractconnection.com";

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

  # Root domain served by Caddy file_server.
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
