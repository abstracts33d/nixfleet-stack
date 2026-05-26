# buildbot-nix unconditionally enables nginx; we bind it to 127.0.0.1:8011 so
# fleet Caddy fronts TLS+ACME via the entry in _data/services.nix. useHTTPS=true
# makes buildbot construct https webhook/OAuth URLs since Caddy terminates.
# Bootstrap: create Forgejo OAuth app (redirect https://buildbot.lab.internal/auth/login),
# set forgejo.oauthId, re-encrypt buildbot-forgejo-{oauth-secret,token}.age,
# tag repos with topic "fleet-ci", run garage-bootstrap-cluster.sh.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixfleet.ciRunner.buildbotNix;

  # Materialized at activation to keep worker password out of the nix store.
  workersJsonPath = "/var/lib/buildbot-master/workers.json";

  # Must match _data/services.nix entry "buildbot" (Caddy fronts 443).
  internalPort = 8011;

  # nix-daemon post-build-hook: pushes built paths to Garage. $OUT_PATHS set by daemon.
  pushHook = pkgs.writeShellScript "buildbot-cache-push" ''
    set -euf
    export IFS=' '
    exec ${config.nix.package}/bin/nix copy \
      --to "${cfg.cachePush.s3Url}" $OUT_PATHS
  '';
in
{
  # Upstream buildbot-{master,worker} modules imported globally from
  # _fleet-modules.nix — can't import here (fleetInputs is config-dependent, would recurse).
  imports = [ ./options.nix ];

  config = lib.mkMerge [
    # mkForce so an explicit null clears any stale hook left by a prior activation
    # (otherwise daemon fails every subsequent nix build).
    {
      nix.settings.post-build-hook = lib.mkForce (
        if cfg.enable && cfg.cachePush.enable then "${pushHook}" else null
      );
    }

    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.cachePush.enable -> cfg.cachePush.s3Url != "";
          message = "nixfleet.ciRunner.buildbotNix.cachePush.enable requires cachePush.s3Url.";
        }
        {
          assertion = cfg.forgejo.oauthId != "";
          message = "nixfleet.ciRunner.buildbotNix requires forgejo.oauthId (create OAuth app in Forgejo first).";
        }
      ];

      services.buildbot-nix.master = {
        enable = true;
        inherit (cfg) domain admins allowUnauthenticatedControl;
        useHTTPS = true; # Caddy terminates; webhook + OAuth URLs are https.
        workersFile = workersJsonPath;
        inherit (cfg.master) dbUrl;

        authBackend = "gitea";
        gitea = {
          enable = true;
          inherit (cfg.forgejo) instanceUrl;
          inherit (cfg.forgejo) oauthId topic;
          inherit (cfg.forgejo) oauthSecretFile;
          inherit (cfg.forgejo) webhookSecretFile;
          inherit (cfg.forgejo) tokenFile;
          inherit (cfg.forgejo) repoAllowlist;
        };
      };

      services.buildbot-nix.worker = {
        enable = true;
        workers = cfg.workerCount;
        workerPasswordFile = cfg.worker.passwordFile;
      };

      # Bind buildbot's nginx to loopback; Caddy fronts TLS via _data/services.nix.
      services.nginx.virtualHosts.${cfg.domain} = {
        listen = lib.mkForce [
          {
            addr = "127.0.0.1";
            port = internalPort;
            ssl = false;
          }
        ];
        forceSSL = lib.mkForce false;
        addSSL = lib.mkForce false;
        enableACME = lib.mkForce false;
      };

      # Must write workers.json at activation, not preStart: systemd evaluates
      # LoadCredential before ExecStartPre (→ status=243/CREDENTIALS on first deploy).
      system.activationScripts.buildbot-workers-json = {
        deps = [ "agenix" ];
        text = ''
          set -euf
          install -d -m 0755 /var/lib/buildbot-master
          pass=$(cat ${cfg.worker.passwordFile})
          cores=${if cfg.workerCount == 0 then "$(${pkgs.coreutils}/bin/nproc)" else toString cfg.workerCount}
          umask 077
          cat > /var/lib/buildbot-master/workers.json <<EOF
          [{"name": "${config.networking.hostName}", "pass": "$pass", "cores": $cores}]
          EOF
          chmod 600 /var/lib/buildbot-master/workers.json
        '';
      };

      # Peer auth: buildbot system user maps to postgres role over unix socket.
      services.postgresql = lib.mkIf cfg.master.useLocalPostgres {
        ensureDatabases = [ "buildbot" ];
        ensureUsers = [
          {
            name = "buildbot";
            ensureDBOwnership = true;
          }
        ];
      };

      # AWS creds inherited by post-build-hook subprocess (nix copy → Garage).
      systemd.services.nix-daemon.serviceConfig = lib.mkIf cfg.cachePush.enable {
        EnvironmentFile = cfg.cachePush.credentialsFile;
        # Garage (and most S3-compat) reject new-style CRC32 checksums; force legacy mode.
        Environment = [
          "AWS_REQUEST_CHECKSUM_CALCULATION=when_required"
          "AWS_RESPONSE_CHECKSUM_VALIDATION=when_required"
        ];
      };

      networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
        9989 # master<->worker pb (only needed if worker is off-host)
      ];

      nixfleet.persistence.directories = [
        "/var/lib/buildbot-master"
        "/var/lib/buildbot-worker"
      ];
    })
  ];
}
