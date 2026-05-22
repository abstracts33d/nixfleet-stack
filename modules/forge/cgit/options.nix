# cgit forge scope — option declarations.
#
# Read-only HTTP UI for git repositories, typically paired with the
# `gitolite` scope (cgit scans gitolite's repository directory). The
# nginx vhost binds loopback; Caddy fronts the public hostname via
# `_data/services.nix` (service "cgit" → https://git2.lab.internal).
{ lib, ... }:
let
  inherit (lib) types;
in
{
  options.nixfleet.forge.cgit = {
    enable = lib.mkEnableOption "cgit — read-only HTTP UI for git repos";

    virtualHost = lib.mkOption {
      type = types.str;
      example = "git2.lab.internal";
      description = ''
        Hostname for the nginx server-name (and Caddy's reverse-proxy
        target). Must match the upstream Caddy vhost configured via
        `_data/services.nix` (service entry "cgit").
      '';
    };

    port = lib.mkOption {
      type = types.port;
      default = 8012;
      description = ''
        Loopback port the cgit nginx binds on. Caddy reverse-proxies
        public TLS traffic to this port. Default 8012 matches the
        `cgit` entry in `_data/services.nix`.
      '';
    };

    scanPath = lib.mkOption {
      type = types.str;
      default = "/var/lib/gitolite/repositories";
      description = ''
        Directory cgit scans for bare repositories. Default points at
        gitolite's repo storage. Override if cgit serves a different
        repo source.
      '';
    };

    gitHttpBackend.enable = lib.mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable smart-HTTP for `git clone https://<vhost>/<repo>.git`.
        cgit's nginx forwards `*.git/...` paths to git-http-backend.
        Required for fleet hosts to fetch the flake over HTTPS without
        SSH access.
      '';
    };

    rootTitle = lib.mkOption {
      type = types.str;
      default = "fleet repos";
      description = "Banner title shown at the top of the cgit landing page.";
    };

    rootDesc = lib.mkOption {
      type = types.str;
      default = "Read-only browser. Pushes go via SSH to gitolite.";
      description = "Subheading text on the cgit landing page.";
    };
  };
}
