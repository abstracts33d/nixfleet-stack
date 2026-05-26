# Cluster formation is NOT declarative; after deploy run on each node:
#   garage node id; garage node connect <pubkey>@<rpc_public_addr>
#   garage layout assign <node-id> -z <zone> -c <cap>G -t <tag>; garage layout apply --version 1
# S3 API refuses writes until layout is applied.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixfleet.cacheGarage;

  portOf = bindAddr: lib.toInt (lib.last (lib.splitString ":" bindAddr));
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    nixfleet.cacheGarage.package = lib.mkDefault pkgs.garage;

    services.garage = {
      enable = true;
      inherit (cfg) package;
      inherit (cfg) logLevel;

      settings = {
        metadata_dir = cfg.metadataDir;
        data_dir = cfg.dataDir;
        replication_factor = cfg.replicationFactor;

        rpc_bind_addr = cfg.rpc.bindAddr;
        rpc_public_addr = cfg.rpc.publicAddr;
        rpc_secret_file = cfg.rpc.secretFile;

        s3_api = {
          api_bind_addr = cfg.s3.bindAddr;
          s3_region = cfg.s3.region;
          root_domain = cfg.s3.rootDomain;
        };

        s3_web = {
          bind_addr = cfg.s3Web.bindAddr;
          root_domain = cfg.s3Web.rootDomain;
          inherit (cfg.s3Web) index;
        };
      };
    };

    environment.systemPackages = [ cfg.package ];

    # Override DynamicUser=true: impermanent hosts get EXDEV when systemd
    # migrates /var/lib/garage to /var/lib/private/garage across /persist bind.
    users.users.garage = {
      isSystemUser = true;
      group = "garage";
      home = cfg.dataDir;
    };
    users.groups.garage = { };

    systemd.services.garage.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = lib.mkForce "garage";
      Group = lib.mkForce "garage";
      StateDirectory = lib.mkForce "garage";
    };

    # Flip root-owned state to garage after DynamicUser swap. Idempotent.
    system.activationScripts.nixfleet-garage-chown = lib.stringAfter [ "users" ] ''
      install -d -o garage -g garage -m 0700 ${cfg.dataDir} ${cfg.metadataDir}
      chown -R garage:garage ${cfg.dataDir} ${cfg.metadataDir} || true
    '';

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
      (portOf cfg.rpc.bindAddr)
      (portOf cfg.s3.bindAddr)
      (portOf cfg.s3Web.bindAddr)
    ];

    # metadataDir holds node identity; losing it means rejoining the cluster.
    nixfleet.persistence.directories = [
      cfg.dataDir
      cfg.metadataDir
    ];
  };
}
