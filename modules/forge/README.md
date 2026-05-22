# Forge scopes

Self-hosted git-forge family. Each implementation runs a forge
server on the host and exposes the operator's repos for fleet
consumption (cloning, pushing, releases triggering CI). Distinct
from the `gitops/` family — `gitops/` produces URL templates the
control plane consumes; `forge/` is the *deployment* of the forge
itself.

## Convention every forge scope follows

Each impl owns its `nixfleet.<name>.*` option subnamespace
(currently only `nixfleet.forge.*` for forgejo, since forgejo is
the only impl shipped). When/if a second arrives (Gitea standalone,
sourcehut, gitlab-omnibus), it lives at a sibling directory with
its own subnamespace; consumers pick which scope to import.

Common shape across implementations:

- HTTPS frontend assumed to be a separate reverse-proxy scope
  (caddy / nginx) — these forges all run on `localhost:<port>`.
- Bootstrap admin user via `admin.userFile` (one-shot, idempotent
  via marker file).
- Optional declarative repository pre-creation
  (`repositories = [{owner; name; description; …}]`).
- Optional declarative SSH key registration for the admin user
  (`admin.sshKeyFiles`).

## Validated impls

- **`forgejo/`** — wraps upstream `services.forgejo`. Runs the
  Forgejo daemon, sets up the admin user, optionally pre-creates
  repositories and registers SSH keys. URL shape compatible with
  the `gitops.forgejo` channel-refs builder.

## Adding a new impl

Land it as `<name>/{default.nix,options.nix}` here, register
under `flake.scopes.forge.<name>`, and pair it with an entry in
`scopes/gitops/<name>.nix` if its raw-URL shape differs from
Forgejo's. Validation expectation matches the cache-server
discipline: a real fleet exercises both forge + gitops sides
before the registration lands.
