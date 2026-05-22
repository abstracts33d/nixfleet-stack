# buildbot-nix CI driver — option declarations.
#
# Sibling of `forgejo-actions` and `hercules` under `nixfleet.ciRunner.*`.
# Designed for the Garage cache-push pipeline (post-build-hook on the
# worker). Forgejo provides repo hosting + webhooks + OAuth — buildbot
# integrates via the Gitea-compatible API.
{ lib, ... }:
let
  inherit (lib) types;
in
{
  options.nixfleet.ciRunner.buildbotNix = {
    enable = lib.mkEnableOption "buildbot-nix master + worker";

    domain = lib.mkOption {
      type = types.str;
      example = "buildbot.lab.internal";
      description = ''
        Public FQDN of the buildbot master. Used in webhook URLs,
        OAuth redirect URI, and the web UI banner.
      '';
    };

    admins = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "s33d" ];
      description = "Forgejo usernames with admin rights in buildbot.";
    };

    workerCount = lib.mkOption {
      type = types.int;
      default = 0;
      description = "Worker concurrency. 0 = auto-detect CPU cores.";
    };

    allowUnauthenticatedControl = lib.mkOption {
      type = types.bool;
      default = true;
      description = ''
        Skip OAuth for control actions (force build, cancel, restart).
        Safe when buildbot is on a tailnet — the network is the auth
        boundary. Read access stays unauthenticated regardless.
      '';
    };

    master = {
      adminPasswordFile = lib.mkOption {
        type = types.str;
        example = "/run/secrets/buildbot-admin-password";
        description = "HTTP basic auth password for the buildbot admin user (fallback when OAuth is unavailable).";
      };

      useLocalPostgres = lib.mkOption {
        type = types.bool;
        default = true;
        description = ''
          Provision a `buildbot` DB + user on the host's local
          postgres. Set false to point at an external instance via
          master.dbUrl.
        '';
      };

      dbUrl = lib.mkOption {
        type = types.str;
        default = "postgresql://buildbot@/buildbot";
        description = "SQLAlchemy DB URL. Default uses local postgres unix socket auth.";
      };
    };

    worker = {
      passwordFile = lib.mkOption {
        type = types.str;
        example = "/run/secrets/buildbot-worker-password";
        description = "Shared secret between worker and master. Generate 32-byte hex.";
      };
    };

    forgejo = {
      instanceUrl = lib.mkOption {
        type = types.str;
        example = "http://localhost:3001";
        description = "Local Forgejo URL. Loopback when buildbot runs on the same host.";
      };

      tokenFile = lib.mkOption {
        type = types.str;
        example = "/run/secrets/buildbot-forgejo-token";
        description = ''
          Path to Forgejo API token (admin scope). Buildbot uses this
          to read repos, post commit statuses, and auto-create
          webhooks for the projects it watches. Generate manually
          via Forgejo UI: Profile → Settings → Applications.
        '';
      };

      oauthId = lib.mkOption {
        type = types.str;
        example = "abc-123-def-...";
        description = ''
          Forgejo OAuth application client ID. Manually create the
          app at Forgejo UI: Site Admin → Applications → New OAuth2
          App. Redirect URI: https://<domain>/auth/login.
        '';
      };

      oauthSecretFile = lib.mkOption {
        type = types.str;
        example = "/run/secrets/buildbot-forgejo-oauth-secret";
        description = "Path to OAuth client secret (shown once at app creation).";
      };

      webhookSecretFile = lib.mkOption {
        type = types.str;
        example = "/run/secrets/buildbot-forgejo-webhook-secret";
        description = ''
          Shared HMAC secret. Buildbot uses this to verify webhook
          payloads from Forgejo. Generate locally (32-byte hex);
          buildbot auto-provisions webhooks in Forgejo using this
          value via the API.
        '';
      };

      topic = lib.mkOption {
        type = types.str;
        default = "fleet-ci";
        description = ''
          Forgejo topic that marks repos as buildbot-managed.
          Combined with repoAllowlist below — both filters apply.
        '';
      };

      repoAllowlist = lib.mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "abstracts33d/fleet" ];
        description = ''
          Explicit `owner/repo` allowlist. Empty list = no filter
          (rely on topic). Recommended for v1: pin to one repo.
        '';
      };
    };

    cachePush = {
      enable = lib.mkOption {
        type = types.bool;
        default = false;
        description = ''
          Install a Nix `post-build-hook` on the worker that pushes
          every successful build to `cachePush.s3Url`. Affects ALL
          builds on this host, not just buildbot jobs.
        '';
      };

      s3Url = lib.mkOption {
        type = types.str;
        example = "s3://fleet-cache?endpoint=http://lab:3900&region=garage&compression=zstd";
        description = "Nix copy target. Garage S3 API typically `s3://<bucket>?endpoint=...&region=...`.";
      };

      credentialsFile = lib.mkOption {
        type = types.str;
        example = "/run/secrets/garage-ci-creds";
        description = ''
          Path to env file with AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY.
          Generated by scripts/garage-bootstrap-cluster.sh, then
          encrypted via agenix.
        '';
      };
    };

    openFirewall = lib.mkOption {
      type = types.bool;
      default = false;
      description = ''
        Open port 9989 (master↔worker protocol) + HTTP port.
        Off by default — fleet stays on tailnet, no external exposure.
      '';
    };
  };
}
