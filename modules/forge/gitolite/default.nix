# Gitolite forge scope — wraps upstream `services.gitolite`.
#
# Operator bootstrap (one-time after first deploy):
#   1. SSH to the host as the gitolite user to confirm setup:
#        ssh gitolite@<host> info
#      Expect: "hello <operator>, this is gitolite3 ..."
#   2. Clone the admin repo from your workstation:
#        git clone gitolite@<host>:gitolite-admin
#   3. Edit `conf/gitolite.conf` to declare repos + per-repo ACLs.
#      Push to materialize them as bare repos on the host.
#   4. (Optional) Add post-receive hooks under `hooks/` for mirroring
#      to GitHub / triggering buildbot polls / etc.
#
# Web browsing: pair this scope with the `cgit` scope to serve a
# read-only HTTPS view of the repositories directory.
#
# Coexists with Forgejo: gitolite uses the system OpenSSH (port 22)
# via authorized_keys forced commands; Forgejo runs its own embedded
# SSH server on a non-22 port (typically 222). No collision.
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixfleet.forge.gitolite;
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.adminPubkey != "";
        message = "nixfleet.forge.gitolite.enable requires adminPubkey (gitolite refuses to bootstrap without it).";
      }
    ];

    services.gitolite = {
      enable = true;
      inherit (cfg)
        adminPubkey
        dataDir
        user
        group
        description
        ;
    };

    # Bare repos + the gitolite-admin home directory. Losing this dir
    # wipes the cluster's repo state (and operator's pushed config).
    nixfleet.persistence.directories = [ cfg.dataDir ];
  };
}
