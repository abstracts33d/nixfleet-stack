{ lib, ... }:
let
  inherit (lib) types;
in
{
  options.nixfleet.cacheGarage = {
    enable = lib.mkEnableOption "Garage S3-compatible object store (binary cache backend)";

    package = lib.mkOption {
      type = types.package;
      defaultText = lib.literalExpression "pkgs.garage";
      description = "Garage package. Defaults to pkgs.garage in default.nix.";
    };

    replicationFactor = lib.mkOption {
      type = types.enum [
        1
        2
        3
      ];
      default = 2;
      description = ''
        Cluster replication factor. Must match across all cluster
        nodes — Garage refuses to form a cluster with mixed values.
        Two-node lab+krach fleet uses 2.
      '';
    };

    dataDir = lib.mkOption {
      type = types.str;
      default = "/var/lib/garage/data";
      description = "Object data store. Contributes to nixfleet.persistence.directories.";
    };

    metadataDir = lib.mkOption {
      type = types.str;
      default = "/var/lib/garage/meta";
      description = "Cluster metadata + node identity keys. Contributes to nixfleet.persistence.directories.";
    };

    rpc = {
      bindAddr = lib.mkOption {
        type = types.str;
        default = "[::]:3901";
        description = "Inter-node RPC bind address.";
      };

      publicAddr = lib.mkOption {
        type = types.str;
        example = "lab:3901";
        description = ''
          The address peers use to reach this node. Typically the
          host's Tailscale hostname + RPC port. Required — peers
          cannot connect without it.
        '';
      };

      secretFile = lib.mkOption {
        type = types.str;
        example = "/run/secrets/garage-rpc-secret";
        description = ''
          Path to a file containing the 32-byte hex cluster secret
          shared by ALL cluster nodes. Generate once via
          `openssl rand -hex 32` and distribute via agenix.
        '';
      };
    };

    s3 = {
      bindAddr = lib.mkOption {
        type = types.str;
        default = "[::]:3900";
        description = "S3 API bind address. This is what `nix copy --to s3://...?endpoint=...` targets.";
      };

      region = lib.mkOption {
        type = types.str;
        default = "garage";
        description = "Logical S3 region name. Must match the region in the substituter URL.";
      };

      rootDomain = lib.mkOption {
        type = types.str;
        default = ".s3.garage";
        description = "Virtual-host-style root domain. Unused for path-style access (the nix-copy path).";
      };
    };

    s3Web = {
      bindAddr = lib.mkOption {
        type = types.str;
        default = "[::]:3902";
        description = ''
          Public read-only bind. Hosts hit this for substituter reads.
          The S3 API also serves reads, but s3-web is the cleaner
          public surface — no auth, plain HTTP.
        '';
      };

      rootDomain = lib.mkOption {
        type = types.str;
        default = ".web.garage";
        description = "Virtual-host root for bucket-as-subdomain mapping.";
      };

      index = lib.mkOption {
        type = types.str;
        default = "index.html";
        description = "Default file served for directory requests.";
      };
    };

    openFirewall = lib.mkOption {
      type = types.bool;
      default = false;
      description = ''
        Open RPC + S3 + s3-web ports. Off by default — fleet hosts
        reach each other over Tailscale, which already crosses host
        firewalls without needing TCP rules.
      '';
    };

    logLevel = lib.mkOption {
      type = types.enum [
        "error"
        "warn"
        "info"
        "debug"
        "trace"
      ];
      default = "info";
      description = "Garage log level.";
    };
  };
}
