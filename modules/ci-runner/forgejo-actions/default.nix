# Forgejo Actions self-hosted runner driver. Sibling of `hercules` driver
# under `nixfleet.ciRunner.*`; both can coexist on one host.
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

    # `.path` is additive — merges packages into PATH without clobbering
    # HOME/LOCALE_ARCHIVE/TZDIR (which `serviceConfig.Environment = PATH=...`
    # would replace, breaking the runner at activation). Consumers extend
    # via `systemd.services.gitea-runner-nixfleet.path = [ ... ]`.
    # `after`/`wants` on local forgejo prevents a rebuild race where runner
    # boots before forgejo accepts connections and exits 1.
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
      # Static user instead of upstream DynamicUser=true: DynamicUser
      # idmaps StateDirectory with `noexec`, fatal for `runs-on: native`
      # compile+execute workflows. PrivateTmp off: upstream's 1.6 GB tmpfs
      # hits ENOSPC during `attic push` of multi-GB nars + nixfleet-release
      # tempfiles. NB: DynamicUser=true ignores explicit PrivateTmp=false
      # override (implicit always wins) — keep static-user.
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

    # DynamicUser=true leaves /var/lib/gitea-runner as a symlink to
    # /var/lib/private/gitea-runner. Toggling to static user trips
    # StateDirectory setup with status=238/STATE_DIRECTORY. Strip stale
    # symlink before activation; idempotent (regular dirs untouched).
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
