# cgit forge scope — wraps upstream `services.cgit.<name>`.
#
# Reverse-proxy story: same pattern as the buildbot-nix scope. cgit's
# upstream module unconditionally configures a `services.nginx`
# virtualHost on port 80. We override the listen to bind on
# 127.0.0.1:<cfg.port>, then `_data/services.nix` (service "cgit")
# tells Caddy to terminate TLS for `https://<virtualHost>/` and
# reverse-proxy to that port.
#
# Read-only browse: nginx serves cgit-cgi for `/`, git-http-backend
# for `/*.git/`. Operators push to repos over SSH via the gitolite
# scope; cgit + nginx never authenticate writes.
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
      # Gitolite-managed repos don't drop a `git-daemon-export-ok`
      # marker file. Disable the upstream check so smart-HTTP serves
      # them anyway. Read-only auth still applies via gitolite ACLs
      # at the SSH layer — HTTP is anonymous by design.
      gitHttpBackend.checkExportOkFiles = false;
      settings = {
        root-title = cfg.rootTitle;
        root-desc = cfg.rootDesc;
        # Enable per-commit diff, blame, etc.
        enable-commit-graph = true;
        enable-log-filecount = true;
        enable-log-linecount = true;
        enable-index-links = true;
        enable-blame = true;
        # cgit can compress on the fly — small repos are cheap.
        snapshots = "tar.gz zip";
        # Scan-path option in cgit's own config (also set via scanPath
        # in the NixOS module — set explicitly so cgit's own scrolling
        # behaviour is correct on each request).
        scan-path = cfg.scanPath;
      };
    };

    # Override the upstream cgit-nginx vhost to bind on loopback only.
    # Caddy in front terminates TLS and reverse-proxies to <loopback>:port.
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

    # cgit itself doesn't keep mutable state (it reads scanPath). No
    # persistence directive needed — the scan target's persistence is
    # the responsibility of whoever owns scanPath (e.g. gitolite scope).

    # Grant the cgit fcgiwrap user read access to gitolite-managed
    # repos. Gitolite creates bare repos mode 0700 owned by gitolite:
    # gitolite, which excludes cgit. POSIX ACLs let us add cgit:rX
    # without changing the owner+group or relaxing gitolite's umask.
    # The default ACL ensures repos created later inherit the same
    # grant. Idempotent — runs on every activation.
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
