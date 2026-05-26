# osquery agent — per-host options shared by NixOS + Darwin variants.
{ lib, ... }:
{
  options.nixfleet.osquery = {
    enable = lib.mkEnableOption "osquery agent (per-host) with privacy tier-B allowlist";

    fleetDmUrl = lib.mkOption {
      type = lib.types.str;
      example = "https://fleet.lab.internal";
      description = "fleet-dm endpoint URL. On lab itself, override to http://localhost:<port>.";
    };

    enrollSecretFile = lib.mkOption {
      type = lib.types.path;
      example = "/run/agenix/fleet-dm-enroll-secret";
      description = "Path to a file containing the fleet-dm enrollment secret (UUID).";
    };

    hostTier = lib.mkOption {
      type = lib.types.enum [
        "workstation"
        "server"
      ];
      default = "workstation";
      description = ''
        Allowlist tier. workstation = Tier B baseline (privacy-strict, no /home recursion).
        server = Tier B + relaxed (lab-extras pack with file_events on /etc, /var/log).
      '';
    };

    logForwarding.lokiFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/log/osquery/results.log";
      description = "Filesystem log path tailed by Vector → Loki.";
    };

    nodeKeyPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/osquery/node_key";
      description = "Cached node_key path. Persistence-tagged on impermanence hosts.";
    };
  };
}
