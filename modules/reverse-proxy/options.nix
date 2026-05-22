# Reverse-proxy scope (Caddy) — option declarations.
{ lib, ... }:
let
  inherit (lib) types;
in
{
  options.nixfleet.reverseProxy = {
    enable = lib.mkEnableOption "Caddy reverse proxy for fleet-hosted services";

    email = lib.mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "ops@example.com";
      description = "Contact email for ACME. Required when any site uses tls.mode = \"acme\".";
    };

    sites = lib.mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            host = lib.mkOption {
              type = types.str;
              description = "Virtual host (FQDN) Caddy serves.";
            };
            upstream = lib.mkOption {
              type = types.str;
              description = "Upstream target passed to reverse_proxy. E.g. \"localhost:3001\".";
            };
            tls = {
              mode = lib.mkOption {
                type = types.enum [
                  "internal"
                  "acme"
                  "off"
                ];
                default = "internal";
                description = "\"internal\" = Caddy's internal CA; \"acme\" = Let's Encrypt; \"off\" = plain HTTP.";
              };
              extraDirectives = lib.mkOption {
                type = types.lines;
                default = "";
                description = "Extra Caddyfile lines inside the tls block. E.g. ACME DNS-01 provider config.";
              };
            };
            extraDirectives = lib.mkOption {
              type = types.lines;
              default = "";
              description = "Extra Caddyfile lines for this site (before reverse_proxy).";
            };
          };
        }
      );
      default = [ ];
      description = "List of reverse-proxied vhosts.";
    };

    tailscale.useMagicDNS = lib.mkOption {
      type = types.bool;
      default = false;
      description = "Assume hostnames resolve over Tailscale MagicDNS. Informational flag consumed by downstream tooling.";
    };

    internalCa = {
      exportCertFile = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "/var/lib/caddy/ca-root.crt";
        description = "When non-null, copy Caddy's internal-CA root certificate here so downstream hosts can trust *.internal vhosts.";
      };
    };
  };
}
