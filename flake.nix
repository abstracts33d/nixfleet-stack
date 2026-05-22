{
  description = "Lab-stack modules — coordinator + self-hosted services consuming nixfleet";

  inputs = {
    nixfleet.url = "github:arcanesys/nixfleet";
    nixpkgs.follows = "nixfleet/nixpkgs";
    flake-parts.follows = "nixfleet/flake-parts";
    treefmt-nix.follows = "nixfleet/treefmt-nix";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    attic = {
      url = "github:booxter/attic/newer-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    buildbot-nix.url = "github:nix-community/buildbot-nix";
    buildbot-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      imports = [
        inputs.treefmt-nix.flakeModule
      ];

      perSystem =
        { pkgs, ... }:
        {
          treefmt = {
            projectRootFile = "flake.nix";
            programs = {
              nixfmt.enable = true;
              nixfmt.package = pkgs.nixfmt;
              shfmt.enable = true;
              deadnix.enable = true;
              statix.enable = true;
            };
          };
        };

      flake.nixosModules =
        let
          # Granular modules — each maps to one subtree under modules/.
          coordinator-meta = ./modules/coordinator;
          cache-server-harmonia = ./modules/cache-server/harmonia;
          cache-server-garage = ./modules/cache-server/garage;
          cache-server-attic = ./modules/cache-server/attic-server;
          ci-runner-buildbot = ./modules/ci-runner/buildbot-nix;
          ci-runner-forgejo = ./modules/ci-runner/forgejo-actions;
          ci-runner-hercules = ./modules/ci-runner/hercules;
          forge-forgejo = ./modules/forge/forgejo;
          forge-gitolite = ./modules/forge/gitolite;
          forge-cgit = ./modules/forge/cgit;
          backup-server = ./modules/backup-server;
          monitoring-server = ./modules/monitoring-server;
          reverse-proxy = ./modules/reverse-proxy;
          lab-apps = ./modules/lab-apps;
        in
        {
          # Granular — pick what you need.
          inherit
            coordinator-meta
            cache-server-harmonia
            cache-server-garage
            cache-server-attic
            ci-runner-buildbot
            ci-runner-forgejo
            ci-runner-hercules
            forge-forgejo
            forge-gitolite
            forge-cgit
            backup-server
            monitoring-server
            reverse-proxy
            lab-apps
            ;

          # Aggregator — everything at once. Downstream just imports
          # `nixfleet-stack.nixosModules.lab-stack` to get the whole stack.
          # External nixosModules that the underlying modules require
          # (buildbot-nix master+worker) are pulled in here so consumers
          # don't have to wire them separately.
          lab-stack =
            { ... }:
            {
              imports = [
                inputs.buildbot-nix.nixosModules.buildbot-master
                inputs.buildbot-nix.nixosModules.buildbot-worker

                # Coordinator stack
                coordinator-meta
                cache-server-harmonia
                cache-server-garage
                cache-server-attic
                ci-runner-buildbot
                ci-runner-forgejo
                ci-runner-hercules
                forge-forgejo
                forge-gitolite
                forge-cgit
                backup-server
                monitoring-server
                reverse-proxy

                # Monitoring-server scrape config (fleet-specific scrape jobs)
                ./modules/monitoring-server/scrape-config.nix

                # Lab-apps — concrete services
                "${lab-apps}/base.nix"
                "${lab-apps}/adguard.nix"
                "${lab-apps}/grafana.nix"
                "${lab-apps}/loki.nix"
                "${lab-apps}/ntfy.nix"
                "${lab-apps}/caddy.nix"
                "${lab-apps}/atuin.nix"
                "${lab-apps}/restic-server.nix"
                "${lab-apps}/samba.nix"
                "${lab-apps}/jellyfin.nix"
                "${lab-apps}/immich.nix"
                "${lab-apps}/home-assistant"
                "${lab-apps}/homepage.nix"
                "${lab-apps}/cloudflared.nix"
              ];
            };
        };
    };
}
