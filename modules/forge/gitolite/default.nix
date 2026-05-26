# Bootstrap: `ssh gitolite@<host> info`, then `git clone gitolite@<host>:gitolite-admin`
# and edit conf/gitolite.conf to declare repos+ACLs. Pair with cgit scope for web view.
# Coexists with Forgejo: gitolite uses OpenSSH :22 (forced command); Forgejo binds :222.
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

    # Holds bare repos + gitolite-admin home; losing it wipes repo state.
    nixfleet.persistence.directories = [ cfg.dataDir ];
  };
}
