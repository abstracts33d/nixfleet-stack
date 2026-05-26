{ lib, ... }:
let
  inherit (lib) types;
in
{
  options.nixfleet.forge.gitolite = {
    enable = lib.mkEnableOption "Gitolite — SSH-only declarative git hosting";

    adminPubkey = lib.mkOption {
      type = types.str;
      example = "ssh-ed25519 AAAA... operator@host";
      description = ''
        Operator's SSH public key that owns the bootstrap
        `gitolite-admin` repo. Subsequent admin pushes (adding repos,
        changing ACLs) come from clones of that repo. Cannot be empty
        at first activation — gitolite creates the admin repo using
        this key and refuses to proceed without it.
      '';
    };

    dataDir = lib.mkOption {
      type = types.str;
      default = "/var/lib/gitolite";
      description = ''
        Gitolite home + state root. Bare repos live under
        `<dataDir>/repositories/`. Contributes to
        `nixfleet.persistence.directories`.
      '';
    };

    user = lib.mkOption {
      type = types.str;
      default = "gitolite";
      description = ''
        System user that owns the dataDir. Operators connect via
        `ssh <user>@<host>` to push/pull; OpenSSH matches their
        authorized_keys entry to the gitolite-shell forced command,
        which then routes git commands.
      '';
    };

    group = lib.mkOption {
      type = types.str;
      default = "gitolite";
      description = "System group for the gitolite user.";
    };

    description = lib.mkOption {
      type = types.str;
      default = "Gitolite repo hosting on this fleet";
      description = "GECOS / description string for the gitolite user account.";
    };
  };
}
