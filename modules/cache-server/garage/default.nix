# Garage scope — distributed S3-compatible object store used as a
# binary-cache backend. Pushers (`nix copy --to s3://...`) sign
# client-side; Garage stores opaque blobs and serves them over s3-web.
#
# Alternatives in scopes: `harmonia` (lab-local, no cluster), `attic-server`
# (token-authed, chunked dedup). Garage is the choice when you want
# multi-node availability + zero-trust public reads.
#
# Cluster formation is NOT declarative — after deploy, run once per
# new cluster:
#   garage node id   # on each node, capture <pubkey>@<rpc_public_addr>
#   garage node connect <other-node-pubkey>@<other-rpc-public-addr>
#   garage layout assign <node-id> -z <zone> -c <capacity>G -t <tag>
#   garage layout apply --version 1
#
# Until layout is applied, the S3 API will refuse writes.
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

    # garage CLI in operator PATH for cluster formation + GC ops.
    environment.systemPackages = [ cfg.package ];

    # Static user override. Upstream services.garage sets DynamicUser=true,
    # which on impermanent hosts trips an EXDEV at first activation when
    # systemd tries to migrate /var/lib/garage → /var/lib/private/garage
    # across the /persist bind mount. Same trap as in our feedback memory:
    # "DynamicUser + StateDirectory on impermanent hosts → EXDEV at first
    # migration; default to fixed user."
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

    # On first activation after the DynamicUser swap, any pre-existing
    # root-owned state dirs need their ownership flipped. Idempotent.
    system.activationScripts.nixfleet-garage-chown = lib.stringAfter [ "users" ] ''
      install -d -o garage -g garage -m 0700 ${cfg.dataDir} ${cfg.metadataDir}
      chown -R garage:garage ${cfg.dataDir} ${cfg.metadataDir} || true
    '';

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
      (portOf cfg.rpc.bindAddr)
      (portOf cfg.s3.bindAddr)
      (portOf cfg.s3Web.bindAddr)
    ];

    # Node identity keys live in metadataDir — losing them means the
    # node loses its cluster membership and has to rejoin via layout.
    nixfleet.persistence.directories = [
      cfg.dataDir
      cfg.metadataDir
    ];
  };
}
