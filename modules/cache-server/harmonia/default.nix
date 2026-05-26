{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.nixfleet-cache-server;
  # Readiness gate: actix-web in harmonia 3.x registers routes lazily across workers,
  # so a unit "started" by systemd can briefly 404 on /nix-cache-info while workers
  # warm up. Agents probing in that window mark rollouts Failed. Hold the unit in
  # `activating` until /nix-cache-info actually answers 200.
  waitReady = pkgs.writeShellScript "harmonia-wait-ready" ''
    set -eu
    for _ in $(seq 1 60); do
      if ${pkgs.curl}/bin/curl -sf --max-time 2 \
        "http://localhost:${toString cfg.port}/nix-cache-info" >/dev/null; then
        exit 0
      fi
      sleep 1
    done
    echo "harmonia did not serve /nix-cache-info within 60s" >&2
    exit 1
  '';
in
{
  options.services.nixfleet-cache-server = {
    enable = lib.mkEnableOption "NixFleet binary cache server (harmonia)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 5000;
      description = "Port to listen on.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the cache server port in the firewall.";
    };

    signingKeyFile = lib.mkOption {
      type = lib.types.str;
      example = "/run/secrets/cache-signing-key";
      description = ''
        Path to the Nix signing key file for on-the-fly signing.

        IMPORTANT: this file is read by the upstream `services.harmonia.cache`
        module which runs as the `harmonia` system user, NOT root. The path
        you supply here must be readable by `harmonia` - typically by chowning
        the secret to `harmonia:harmonia` after decryption. With agenix, set
        `age.secrets.<name>.owner = "harmonia"`. With sops-nix, set
        `sops.secrets.<name>.owner = "harmonia"`. Other secret stores have
        equivalent options.

        On boot, harmonia silently fails to start if the file is owned by
        root and mode 0600 - the only signal in the journal is "Permission
        denied" from the harmonia unit, which is easy to miss the first time.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.harmonia.cache = {
      enable = true;
      signKeyPaths = [ cfg.signingKeyFile ];
      settings.bind = "0.0.0.0:${toString cfg.port}";
    };

    # Sign at build/copy time (needed for `nix copy --to ssh://host`).
    nix.settings.secret-key-files = [ cfg.signingKeyFile ];

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

    systemd.services.harmonia.serviceConfig.ExecStartPost = [ "${waitReady}" ];
  };
}
