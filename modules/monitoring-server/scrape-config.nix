# Fleet-specific Prometheus scrape jobs (lab only). Base config, alerts,
# blackbox, TSDB persistence live in the monitoring-server scope.
{
  config,
  lib,
  pkgs,
  fleetServices,
  fleetNixosHosts,
  ...
}:
let
  servicesData = fleetServices;
  blackboxExclude = [ "hass" ];
  blackboxOverrides = {
    restic = {
      module = "http_any";
    };
  };

  serviceProbes = lib.mapAttrsToList (name: svc: {
    inherit name;
    target = "http://localhost:${toString svc.port}";
    module = (blackboxOverrides.${name} or { }).module or "http_2xx";
  }) (removeAttrs servicesData blackboxExclude);
in
lib.mkIf config.fleet.server.enable {
  nixfleet.monitoring.server = {
    enable = true;

    targets = map (host: "${host}:9100") fleetNixosHosts;

    alerts = {
      controlPlane = true;
      coordinator = config.nixfleet.coordinator.enable;
    };

    # Alertmanager → ntfy (port 2586, topic nixfleet-alerts). Subscribe
    # via app at https://ntfy.lab.internal or
    # `curl -s https://ntfy.lab.internal/nixfleet-alerts/json`.
    alertmanager.enable = true;

    blackbox = {
      enable = true;
      probes = serviceProbes;
    };

    extraScrapeConfigs = [
      {
        job_name = "node-darwin";
        static_configs = [
          {
            targets = [ "aether:9100" ];
            labels.os = "darwin";
          }
        ];
        # Hostname-extraction relabel matches the linux node job so
        # aether gets a clean `hostname` label for dashboard drill-down.
        relabel_configs = [
          {
            source_labels = [ "instance" ];
            regex = "(.+):[0-9]+";
            target_label = "hostname";
            replacement = "$1";
          }
        ];
      }
      {
        job_name = "nixfleet-cp";
        scheme = "https";
        tls_config = {
          ca_file = "/etc/nixfleet/fleet-ca.pem";
          cert_file = "/var/lib/nixfleet/agent-cert.pem";
          # PKCS#8 export from SSH host key, written by
          # nixfleet-agent-mtls-key-export below; group-readable by
          # `nixfleet-mtls` (prometheus + caddy).
          key_file = "/var/lib/nixfleet/agent-mtls-key.pem";
        };
        static_configs = [ { targets = [ "lab:8080" ]; } ];
      }
      {
        job_name = "caddy";
        static_configs = [ { targets = [ "127.0.0.1:2019" ]; } ];
      }
      {
        job_name = "homeassistant";
        metrics_path = "/api/prometheus";
        bearer_token_file = config.age.secrets."hass-prometheus-token".path;
        static_configs = [ { targets = [ "127.0.0.1:8123" ]; } ];
      }
    ];
  };

  # Convert SSH host key to PKCS#8 PEM for local mTLS scrape clients
  # (Prometheus, fleet-status). ssh-keygen's `-m PEM` for ed25519 emits
  # OpenSSH-PEM, not PKCS#8 (verified empirically); python cryptography
  # handles ed25519 OpenSSH→PKCS#8 cleanly. Canonical key untouched.
  users.groups.nixfleet-mtls = { };
  users.users.prometheus.extraGroups = [ "nixfleet-mtls" ];
  users.users.caddy.extraGroups = [ "nixfleet-mtls" ];
  systemd.services.nixfleet-agent-mtls-key-export =
    let
      py = pkgs.python3.withPackages (ps: [ ps.cryptography ]);
    in
    {
      description = "Export SSH host key as PKCS#8 PEM for local mTLS scrape clients";
      wantedBy = [ "multi-user.target" ];
      before = [
        "prometheus.service"
        "caddy.service"
      ];
      after = [ "sshd.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -eu
        OUT=/var/lib/nixfleet/agent-mtls-key.pem
        TMP=$(mktemp /var/lib/nixfleet/.agent-mtls-key.pem.XXXXXX)
        trap "rm -f $TMP" EXIT
        install -d -m 0755 /var/lib/nixfleet
        ${py}/bin/python3 - <<'PY' > "$TMP"
        import sys
        from cryptography.hazmat.primitives.serialization import (
            load_ssh_private_key, Encoding, PrivateFormat, NoEncryption,
        )
        with open("/etc/ssh/ssh_host_ed25519_key", "rb") as f:
            key = load_ssh_private_key(f.read(), password=None)
        sys.stdout.buffer.write(
            key.private_bytes(Encoding.PEM, PrivateFormat.PKCS8, NoEncryption())
        )
        PY
        chmod 0640 "$TMP"
        chgrp nixfleet-mtls "$TMP"
        mv "$TMP" "$OUT"
        trap - EXIT
      '';
    };
}
