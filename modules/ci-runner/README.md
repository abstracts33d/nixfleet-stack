# CI-runner scopes

Pluggable CI-runner driver family. Each driver registers with a
CI orchestrator (Forgejo Actions, Hercules, future ones) and
executes jobs against the local Nix store.

## Convention every ci-runner scope follows

Each driver owns its `nixfleet.ciRunner.<name>.*` option
subnamespace under the shared `nixfleet.ciRunner.*` umbrella.
Drivers can coexist on the same host — different services,
different option subtrees, different state dirs. A consumer
imports one or both depending on their CI topology.

- **enable** flag (`nixfleet.ciRunner.<driver>.enable`) gates
  systemd service registration and any persisted state dir
  contributions.
- **token / credential file** path (different shape per driver:
  `agentTokenFile` for hercules, `registrationTokenFile` for
  forgejo-actions).
- **capacity / concurrency** knob.
- Optional **labels / instance-name** for multi-runner registries.

## Validated drivers

- **`forgejo-actions/`** — Forgejo Actions self-hosted runner
  (`services.gitea-actions-runner` with `pkgs.forgejo-runner`).
  GitHub-Actions-compatible workflow language; `runs-on: native`
  for direct-host execution; container labels for sandbox
  workflows. Used on lab.
- **`hercules/`** — Hercules CI agent (Nix-native:
  `services.hercules-ci-agent`). Pulls jobs from Hercules cloud
  or self-hosted Hercules CI. Driver of choice when the CI
  workflow IS Nix evaluation rather than a generic shell pipeline.

## Adding a new driver

Land it as `<name>/{default.nix,options.nix}` here, register
under `flake.scopes.ci-runner.<name>`, and document any host-side
PATH / state-dir / persistence integration the runner needs (see
`forgejo-actions/default.nix` for the full pattern — it carries
the most operational knobs).
