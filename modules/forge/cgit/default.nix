# cgit upstream always opens an nginx vhost on :80; bind to 127.0.0.1:<cfg.port>
# and front via Caddy through _data/services.nix. Read-only browse only; writes
# go through gitolite over SSH.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixfleet.forge.cgit;
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.virtualHost != "";
        message = "nixfleet.forge.cgit.enable requires virtualHost (the public hostname Caddy + nginx route on).";
      }
    ];

    services.cgit.main = {
      enable = true;
      nginx.virtualHost = cfg.virtualHost;
      inherit (cfg) scanPath;
      gitHttpBackend.enable = cfg.gitHttpBackend.enable;
      # Gitolite repos lack git-daemon-export-ok; HTTP is anonymous read-only by design.
      gitHttpBackend.checkExportOkFiles = false;
      settings = {
        root-title = cfg.rootTitle;
        root-desc = cfg.rootDesc;
        enable-commit-graph = true;
        enable-log-filecount = true;
        enable-log-linecount = true;
        enable-index-links = true;
        enable-blame = true;
        snapshots = "tar.gz zip";
        # Set in cgit's own config too so per-request scroll behaviour matches.
        scan-path = cfg.scanPath;
      };
    };

    services.nginx.virtualHosts.${cfg.virtualHost} = {
      listen = lib.mkForce [
        {
          addr = "127.0.0.1";
          inherit (cfg) port;
          ssl = false;
        }
      ];
      forceSSL = lib.mkForce false;
      addSSL = lib.mkForce false;
      enableACME = lib.mkForce false;
    };

    # Gitolite repos are 0700 gitolite:gitolite; POSIX ACL grants cgit:rX
    # (default ACL → inherited by future repos). Idempotent.
    system.activationScripts.cgit-gitolite-acl =
      lib.mkIf (lib.hasPrefix "/var/lib/gitolite" cfg.scanPath)
        {
          deps = [ "users" ];
          text = ''
            if [ -d ${cfg.scanPath} ]; then
              ${pkgs.acl}/bin/setfacl -m u:cgit:rX /var/lib/gitolite || true
              ${pkgs.acl}/bin/setfacl -R -m u:cgit:rX ${cfg.scanPath} || true
              ${pkgs.acl}/bin/setfacl -d -m u:cgit:rX ${cfg.scanPath} || true
            fi
          '';
        };
  };
}
