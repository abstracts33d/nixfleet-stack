# HTTP binds loopback (consumer fronts reverse proxy); SSH uses :222 by default
# to leave host OpenSSH on :22.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixfleet.forge;
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    services.forgejo = {
      enable = true;
      stateDir = cfg.dataDir;
      database.type = cfg.database.type;
      inherit (cfg) lfs;

      settings = {
        DEFAULT.APP_NAME = cfg.appName;

        server = {
          DOMAIN = cfg.domain;
          ROOT_URL = "https://${cfg.domain}/";
          HTTP_ADDR = cfg.http.addr;
          HTTP_PORT = cfg.http.port;
          SSH_DOMAIN = cfg.domain;
          SSH_PORT = cfg.ssh.port;
          SSH_LISTEN_HOST = cfg.ssh.listenHost;
          START_SSH_SERVER = cfg.ssh.enable;
          # Magic string for inbound SSH (not a system user); enables git@<host> URLs.
          BUILTIN_SSH_SERVER_USER = cfg.ssh.user;
          SSH_USER = cfg.ssh.user;
          LANDING_PAGE = "login";
        };

        service.DISABLE_REGISTRATION = cfg.disableRegistration;
        session.COOKIE_SECURE = true;

        actions = lib.mkIf cfg.actions.enable {
          ENABLED = true;
          DEFAULT_ACTIONS_URL = cfg.actions.defaultActionsUrl;
        };

        mailer = lib.mkIf cfg.smtp.enable {
          ENABLED = true;
          SMTP_ADDR = cfg.smtp.host;
          FROM = cfg.smtp.from;
          USER = cfg.smtp.user;
          PASSWD = lib.mkIf (cfg.smtp.passwordFile != null) "$(cat ${cfg.smtp.passwordFile})";
        };

        repository.DEFAULT_BRANCH = "main";
      };
    };

    # Bootstrap admin + access token via CLI; ssh-keys/repos go through HTTP API
    # (Forgejo LTS 11 has no `admin user add-ssh-key` CLI).
    systemd.services.forgejo = lib.mkIf (cfg.admin.userFile != null) {
      path = [
        pkgs.curl
        pkgs.jq
        pkgs.gnugrep
        pkgs.coreutils
      ];
      preStart = lib.mkAfter ''
        admin_user=""
        if [ ! -f ${cfg.dataDir}/.nixfleet-admin-created ]; then
          if [ -r ${cfg.admin.userFile} ]; then
            IFS=: read -r admin_user admin_email admin_pass < ${cfg.admin.userFile}
            ${pkgs.forgejo}/bin/forgejo admin user create \
              --admin \
              --username "$admin_user" \
              --email "$admin_email" \
              --password "$admin_pass" || true
            touch ${cfg.dataDir}/.nixfleet-admin-created
          fi
        fi

        # Re-read admin_user when marker branch skipped above.
        if [ -z "$admin_user" ] && [ -r ${cfg.admin.userFile} ]; then
          IFS=: read -r admin_user _ _ < ${cfg.admin.userFile}
        fi

        # API token generated once, reused by ssh-keys + repos oneshots.
        token_file=${cfg.dataDir}/.nixfleet-bootstrap-token
        if [ -n "$admin_user" ] && [ ! -f "$token_file" ]; then
          # CLI prints "Access token was successfully created: <40-hex>".
          token=$(${pkgs.forgejo}/bin/forgejo admin user generate-access-token \
            --username "$admin_user" \
            --token-name nixfleet-bootstrap \
            --scopes "write:admin,write:repository,write:user" 2>&1 \
            | grep -oE '[0-9a-f]{40}' | head -1) || true
          if [ -n "$token" ]; then
            umask 077
            printf '%s' "$token" > "$token_file"
          fi
        fi

        # SSH-key registration deferred to forgejo-ssh-keys.service (HTTP not up yet).
      '';
    };

    # Separate unit: HTTP isn't bound during forgejo.service preStart.
    systemd.services.forgejo-ssh-keys = lib.mkIf (cfg.admin.sshKeyFiles != [ ]) {
      description = "Declarative Forgejo admin SSH key registration";
      after = [ "forgejo.service" ];
      wants = [ "forgejo.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.curl
        pkgs.jq
        pkgs.coreutils
      ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "forgejo";
        Group = "forgejo";
      };

      script = ''
        set -u

        # After=forgejo.service insufficient (Type=simple active before HTTP binds).
        waited=0
        while [ ! -f ${cfg.dataDir}/.nixfleet-admin-created ] \
           || [ ! -f ${cfg.dataDir}/.nixfleet-bootstrap-token ] \
           || ! curl -sf -o /dev/null "http://127.0.0.1:${toString cfg.http.port}/api/v1/version"; do
          if [ $waited -ge 60 ]; then
            echo "forge-ssh-keys: marker/token/HTTP not ready after 60s, aborting" >&2
            exit 0
          fi
          sleep 1
          waited=$((waited + 1))
        done

        IFS=: read -r admin_user _ _ < ${cfg.admin.userFile}
        token=$(cat ${cfg.dataDir}/.nixfleet-bootstrap-token)

        ${lib.concatMapStringsSep "\n" (keyFile: ''
          if [ -r ${keyFile} ]; then
            key_content="$(cat ${keyFile})"
            if [ -n "$key_content" ]; then
              echo "forge-ssh-keys: registering ${keyFile} for $admin_user" >&2
              # 201 (created) / 422 (duplicate fingerprint) both = ok.
              body=$(jq -nc \
                --arg title "nixfleet-bootstrap-$(basename ${keyFile} .pub)" \
                --arg key "$key_content" \
                '{title: $title, key: $key}')
              status=$(curl -s -o /dev/null -w '%{http_code}' \
                -H "Authorization: token $token" \
                -H "Content-Type: application/json" \
                -d "$body" \
                "http://127.0.0.1:${toString cfg.http.port}/api/v1/admin/users/$admin_user/keys") || status=0
              case "$status" in
                201|422) echo "forge-ssh-keys: ${keyFile} -> HTTP $status (ok)" >&2 ;;
                *) echo "forge-ssh-keys: ${keyFile} -> HTTP $status (failed)" >&2 ;;
              esac
            fi
          else
            echo "forge-ssh-keys: ${keyFile} not readable, skipping" >&2
          fi
        '') cfg.admin.sshKeyFiles}
      '';
    };

    # HTTP API (no `admin repo create` CLI on LTS 11). Same gating as ssh-keys.
    # TODO(v2): pullMirror support (upstream URL + auth).
    systemd.services.forgejo-repositories = lib.mkIf (cfg.repositories != [ ]) {
      description = "Declarative Forgejo repository pre-creation";
      after = [ "forgejo.service" ];
      wants = [ "forgejo.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.curl
        pkgs.jq
        pkgs.coreutils
      ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "forgejo";
        Group = "forgejo";
      };

      script = ''
        set -u

        waited=0
        while [ ! -f ${cfg.dataDir}/.nixfleet-admin-created ] \
           || [ ! -f ${cfg.dataDir}/.nixfleet-bootstrap-token ] \
           || ! curl -sf -o /dev/null "http://127.0.0.1:${toString cfg.http.port}/api/v1/version"; do
          if [ $waited -ge 60 ]; then
            echo "forge-repositories: marker/token/HTTP not ready after 60s, aborting" >&2
            exit 0
          fi
          sleep 1
          waited=$((waited + 1))
        done
        token=$(cat ${cfg.dataDir}/.nixfleet-bootstrap-token)

        ${lib.concatMapStringsSep "\n" (repo: ''
          if [ -d ${cfg.dataDir}/repositories/${repo.owner}/${repo.name}.git ]; then
            echo "forge-repositories: ${repo.owner}/${repo.name} already exists, skipping" >&2
          else
            echo "forge-repositories: creating ${repo.owner}/${repo.name}" >&2
            # 201 / 422 both = ok (on-disk check should have caught duplicates).
            body=$(jq -nc \
              --arg name ${lib.escapeShellArg repo.name} \
              --arg desc ${lib.escapeShellArg repo.description} \
              --arg branch ${lib.escapeShellArg repo.defaultBranch} \
              --argjson private ${if repo.private then "true" else "false"} \
              '{name: $name, description: $desc, default_branch: $branch, private: $private, auto_init: false}')
            status=$(curl -s -o /dev/null -w '%{http_code}' \
              -H "Authorization: token $token" \
              -H "Content-Type: application/json" \
              -d "$body" \
              "http://127.0.0.1:${toString cfg.http.port}/api/v1/admin/users/${repo.owner}/repos") || status=0
            case "$status" in
              201|422) echo "forge-repositories: ${repo.owner}/${repo.name} -> HTTP $status (ok)" >&2 ;;
              *) echo "forge-repositories: ${repo.owner}/${repo.name} -> HTTP $status (failed)" >&2 ;;
            esac
          fi
        '') cfg.repositories}
      '';
    };

    # NixOS sets NoNewPrivileges=true, blocking CAP_NET_BIND_SERVICE; lower
    # ip_unprivileged_port_start instead of fighting caps.
    boot.kernel.sysctl = lib.mkIf (cfg.ssh.enable && cfg.ssh.port < 1024) {
      "net.ipv4.ip_unprivileged_port_start" = cfg.ssh.port;
    };

    networking.firewall.allowedTCPPorts = lib.mkIf (cfg.ssh.enable && cfg.ssh.openFirewall) [
      cfg.ssh.port
    ];

    nixfleet.persistence.directories = [
      {
        directory = cfg.dataDir;
        user = "forgejo";
        group = "forgejo";
        mode = "0750";
      }
    ];

    # forgejo-secrets.service bind-mounts stateDir/custom rw; missing on first
    # boot fails namespace setup with status=226/NAMESPACE.
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir}/custom 0750 forgejo forgejo - -"
    ];
  };
}
