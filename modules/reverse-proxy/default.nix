# Reverse-proxy scope — Caddy with fleet-friendly TLS defaults.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixfleet.reverseProxy;

  mkVhost =
    site:
    let
      tlsBlock =
        if site.tls.mode == "off" then
          ""
        else if site.tls.mode == "internal" then
          "tls internal"
        else
          "tls ${if site.tls.extraDirectives == "" then "" else "{\n${site.tls.extraDirectives}\n}"}";
    in
    {
      name = site.host;
      value.extraConfig = ''
        ${tlsBlock}
        ${site.extraDirectives}
        reverse_proxy ${site.upstream}
      '';
    };

  vhosts = builtins.listToAttrs (map mkVhost cfg.sites);

  anyAcme = lib.any (s: s.tls.mode == "acme") cfg.sites;
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !anyAcme || cfg.email != null;
        message = "nixfleet.reverseProxy.email is required when any site uses tls.mode = \"acme\".";
      }
    ];

    services.caddy = {
      enable = true;
      email = lib.mkIf (cfg.email != null) cfg.email;
      virtualHosts = vhosts;
      globalConfig = ''
        servers {
          metrics
        }
      '';
    };

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

    # Optional: export Caddy's internal CA root to a stable path so
    # downstream fleet hosts can import it into their trust bundle.
    systemd.services.nixfleet-reverse-proxy-ca-export =
      lib.mkIf (cfg.internalCa.exportCertFile != null)
        {
          description = "Export Caddy internal-CA root certificate";
          wantedBy = [ "multi-user.target" ];
          after = [ "caddy.service" ];
          requires = [ "caddy.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          path = [ pkgs.coreutils ];
          script = ''
            src="/var/lib/caddy/pki/authorities/local/root.crt"
            dst="${cfg.internalCa.exportCertFile}"
            if [ -f "$src" ]; then
              install -Dm644 "$src" "$dst"
            fi
          '';
        };
  };
}
