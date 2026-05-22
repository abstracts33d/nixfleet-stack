# nixfleet-stack

Lab-coordinator + self-hosted-services modules consuming the
[nixfleet](https://github.com/arcanesys/nixfleet) framework.

Extracted from
[abstracts33d/fleet](https://github.com/abstracts33d/fleet) so the
personal fleet repo can stay focused on workstation/family hosts while
this flake carries the coordinator and lab-apps stack used by the lab
host.

## What's in here

- **`modules/coordinator/`** — meta-scope that pulls in the full
  coordinator stack (forge, attic-server, ci-runner, reverse-proxy,
  backup-server, tpm-keyslot). Inert unless `nixfleet.coordinator.enable`.
- **`modules/cache-server/`** — Harmonia, Attic, Garage Nix binary caches.
- **`modules/ci-runner/`** — buildbot-nix, forgejo-actions, Hercules CI.
- **`modules/forge/`** — Forgejo, Gitolite + cgit.
- **`modules/backup-server/`** — restic REST server.
- **`modules/monitoring-server/`** — Prometheus + alertmanager + blackbox.
- **`modules/reverse-proxy/`** — Caddy with internal-CA TLS.
- **`modules/lab-apps/`** — concrete service modules: AdGuard, Grafana,
  Loki, ntfy, Caddy, Atuin, Restic-server, Samba, Jellyfin, Immich,
  Home Assistant, Homepage, Cloudflared, arcanesys-website-preview.

## Consumption

```nix
# In a downstream flake:
{
  inputs.nixfleet-stack.url = "github:abstracts33d/nixfleet-stack";
  inputs.nixfleet-stack.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nixfleet-stack.inputs.nixfleet.follows = "nixfleet";

  outputs = { self, nixpkgs, nixfleet-stack, ... }: {
    nixosConfigurations.lab = nixpkgs.lib.nixosSystem {
      modules = [
        # Inject fleet-owned data BEFORE the stack import
        ({ ... }: {
          _module.args.fleetHosts = import ./modules/_data/fleet-hosts.nix;
          _module.args.fleetServices = import ./modules/_data/services.nix;
          _module.args.fleetNixosHosts = [ "krach" "ohm" "lab" "pixel" ];
        })
        nixfleet-stack.nixosModules.lab-stack
        # ... per-host config ...
      ];
    };
  };
}
```

The aggregator `nixosModules.lab-stack` imports every module in this
flake. Granular modules (`nixosModules.coordinator-meta`,
`nixosModules.lab-apps`, individual services) are also exposed for
hosts that want a subset.

## Data injection contract

Consumer fleets MUST set the following module args before importing any
lab-stack module:

| Module arg | Type | Purpose |
|---|---|---|
| `fleetHosts` | `{ "<ip>" = [ "<hostname>" ]; ... }` | IP→hostname map (used by AdGuard rewrites, HA msunpv, Caddy /etc/hosts seeding) |
| `fleetServices` | `{ <name> = { port = <int>; subdomain = "<str>" or null; external = <bool>; ... }; }` | Service catalog (used by Caddy reverse-proxy, Cloudflared ingress, monitoring blackbox probes) |
| `fleetNixosHosts` | `[ "<name>" ... ]` | Names of every NixOS host (used by Prometheus node-exporter scrape targets) |

If your fleet keeps its own `_data/` files under the consumer flake,
mirror those into the args via `_module.args` as shown above. This keeps
nixfleet-stack itself fleet-agnostic.

## License

MIT — see [LICENSE](./LICENSE).
