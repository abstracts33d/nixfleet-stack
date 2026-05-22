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

      flake.nixosModules = {
        # Granular modules — pick what you need.
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

        # Aggregator — every lab-stack module at once. Downstream
        # imports `nixfleet-stack.nixosModules.lab-stack` to get the
        # whole stack. External nixosModules required by underlying
        # modules (buildbot-nix master+worker) are pulled in here so
        # consumers don't have to wire them separately.
        lab-stack =
          { ... }:
          {
            imports = [
              inputs.buildbot-nix.nixosModules.buildbot-master
              inputs.buildbot-nix.nixosModules.buildbot-worker

              # Coordinator stack
              ./modules/coordinator
              ./modules/cache-server/harmonia
              ./modules/cache-server/garage
              ./modules/cache-server/attic-server
              ./modules/ci-runner/buildbot-nix
              ./modules/ci-runner/forgejo-actions
              ./modules/ci-runner/hercules
              ./modules/forge/forgejo
              ./modules/forge/gitolite
              ./modules/forge/cgit
              ./modules/backup-server
              ./modules/monitoring-server
              ./modules/reverse-proxy

              # Monitoring-server scrape config (fleet-specific scrape jobs)
              ./modules/monitoring-server/scrape-config.nix

              # Lab-apps — concrete services
              ./modules/lab-apps/base.nix
              ./modules/lab-apps/adguard.nix
              ./modules/lab-apps/grafana.nix
              ./modules/lab-apps/loki.nix
              ./modules/lab-apps/ntfy.nix
              ./modules/lab-apps/caddy.nix
              ./modules/lab-apps/atuin.nix
              ./modules/lab-apps/restic-server.nix
              ./modules/lab-apps/samba.nix
              ./modules/lab-apps/jellyfin.nix
              ./modules/lab-apps/immich.nix
              ./modules/lab-apps/home-assistant
              ./modules/lab-apps/homepage.nix
              ./modules/lab-apps/cloudflared.nix
            ];
          };
      };
    };
}
