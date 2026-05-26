{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixfleet.ciRunner.forgejoActions;
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.registrationTokenFile != null;
        message = "nixfleet.ciRunner.forgejoActions.enable requires forgejoActions.registrationTokenFile.";
      }
    ];

    services.gitea-actions-runner = {
      package = pkgs.forgejo-runner;
      instances.nixfleet = {
        enable = true;
        inherit (cfg) name;
        url = cfg.instanceUrl;
        tokenFile = cfg.registrationTokenFile;
        inherit (cfg) labels;
        settings = {
          runner.capacity = cfg.capacity;
          container.enable = cfg.enableContainers;
          log.level = "info";
        };
      };
    };

    # Use .path (additive) instead of serviceConfig.Environment=PATH= which
    # would clobber HOME/LOCALE_ARCHIVE/TZDIR. after/wants gates the
    # rebuild race where runner exits 1 before forgejo accepts connections.
    systemd.services.gitea-runner-nixfleet = {
      path = with pkgs; [
        config.nix.package
        bash
        coreutils
        findutils
        gnugrep
        gnused
        gawk
        gnutar
        gzip
        git
        jq
        curl
        openssl
      ];
      # Static user: DynamicUser idmaps StateDir noexec (breaks `runs-on: native`)
      # and forces a 1.6GB tmpfs that ENOSPCs on `attic push` of multi-GB nars
      # (DynamicUser=true ignores explicit PrivateTmp=false; only static user works).
      serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = lib.mkForce "gitea-runner";
        Group = lib.mkForce "gitea-runner";
        PrivateTmp = lib.mkForce false;
      };
    }
    //
      lib.optionalAttrs
        (
          lib.hasPrefix "http://localhost" cfg.instanceUrl || lib.hasPrefix "http://127.0.0.1" cfg.instanceUrl
        )
        {
          after = [ "forgejo.service" ];
          wants = [ "forgejo.service" ];
        };

    # Strip stale /var/lib/private/* symlink left by prior DynamicUser=true
    # (else static-user activation fails status=238/STATE_DIRECTORY). Idempotent.
    system.activationScripts.nixfleet-gitea-runner-statedir = ''
      if [ -L /var/lib/gitea-runner ]; then
        rm /var/lib/gitea-runner
      fi
    '';

    users.users.gitea-runner = {
      isSystemUser = true;
      group = "gitea-runner";
      home = "/var/lib/gitea-runner";
    };
    users.groups.gitea-runner = { };

    nixfleet.persistence.directories = [ "/var/lib/gitea-runner" ];
  };
}
