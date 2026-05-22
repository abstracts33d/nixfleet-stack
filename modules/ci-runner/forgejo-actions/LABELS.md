# Forgejo runner label contract

Workflow authors targeting the lab runner (`gitea-runner-nixfleet`)
**must** set `runs-on: native` or `runs-on: nixos`. Targeting
`ubuntu-latest` (or any github-hosted label) silently no-ops on
forgejo — the workflow appears configured but never executes,
because no runner advertises that label.

## How the runner advertises labels

The scope (`modules/scopes/ci-runner/forgejo-actions`) registers
the runner with two labels:

```nix
labels = ["nixos:host" "native:host"];
```

The `:host` suffix is **executor metadata**, not part of the label
forgejo matches against. Forgejo strips it before label-matching,
so workflows reference the bare label:

| Workflow line       | Matches because runner advertises |
| ------------------- | --------------------------------- |
| `runs-on: native`   | `native:host`                     |
| `runs-on: nixos`    | `nixos:host`                      |
| `runs-on: ubuntu-latest` | nothing — workflow stalls    |

Both labels resolve to the same physical runner; pick whichever
reads more clearly in the workflow. Existing repos use `native`.

## What the runner provides

The `forgejo-actions/default.nix` module extends the runner's PATH
with `nix`, `bash`, `coreutils`, `findutils`, `gnugrep`, `gnused`,
`gawk`, `gnutar`, `gzip`, `git`, `jq`, `curl`, `openssl`. The
runner executes jobs **directly on the host** (not in a container),
so workflow steps inherit the host's nixos environment, store, and
substituters.

If a workflow needs additional tools (e.g. `attic-client`,
`tpm-sign`), the consuming host config extends the runner's path:

```nix
systemd.services.gitea-runner-nixfleet.path = [ pkgs.attic-client ];
```

The lab host config wires this up for attic + tpm-sign — see
`hosts/lab/default.nix`.

## Static system user, not DynamicUser

The runner unit overrides nixpkgs' `DynamicUser=true` default to a
static `gitea-runner` system user. `DynamicUser=true` implies an
idmapped `StateDirectory=` bind mount that systemd hardens with
`noexec`, which kills any workflow that compiles + executes
artifacts under the runner's working dir — cargo build scripts,
test binaries, anything that lands in `target/`. Static user keeps
the state dir as a regular bind on the persisted btrfs subvol:
exec-clean, gigabytes of headroom, cache survives reboots.

Workflows that compile native code can therefore use cargo's
default `$PWD/target` directly — no `CARGO_TARGET_DIR` redirect
needed.

## Why containers are off

`enableContainers = false` is the default. Container support
needs docker/podman + image management; lab's CI workload
(nix builds, nix flake check, nix run .#validate) wants the
host's nix store and substituter config, which a container
sandbox isolates away. Stay on `native:host` until a workflow
actually needs container isolation.

## Adding a new workflow

```yaml
on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  build:
    runs-on: native    # NOT ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: nix flake check --no-build
```

The `actions/checkout@v4` action works on forgejo —
gitea-actions-runner ships with a github-actions-compatible action
shim.
