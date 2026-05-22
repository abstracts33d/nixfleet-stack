# Cache-server scopes

Pluggable nix-binary-cache server family. Each implementation
serves the standard nix-cache HTTP wire protocol so any consumer
can use it via the framework's `services.nixfleet-cache.{cacheUrl,
publicKey}` client module without knowing which server is upstream.

## Convention every cache-server scope follows

Each impl's option tree lives under its native namespace
(`services.nixfleet-cache-server.*` for the harmonia wrapper,
`nixfleet.atticServer.*` for attic — driver-specific shapes are
preserved rather than forced into a unified attrset). Both:

- expose a port + listen address option,
- accept a `signingKeyFile` (or token, for cloud caches),
- contribute their persisted state dirs to
  `nixfleet.persistence.directories` when persistence is on,
- assume a reverse-proxy (caddy / nginx / traefik) terminates TLS
  upstream — none of them implement TLS themselves.

Choosing between them is a fleet decision; the framework is
agnostic. Operators can run both on a single host (different
ports), but the typical pattern is one per fleet.

## Validated impls

- **`harmonia/`** — wraps upstream `services.harmonia.cache`. Signs
  paths during `nix copy --to ssh://`; serves over plain HTTP from
  the local store. Lightweight, no separate database.
- **`attic-server/`** — wraps upstream `atticd` (the `attic`
  binary-cache server). Token-authed, multi-tenant via
  cache-keys, content-addressed dedup. Used by the abstracts33d
  fleet's lab coordinator.

## Adding a new impl (e.g. cachix-self-hosted, nix-serve, S3)

Land it as `<name>/{default.nix,options.nix}` here, then register
in `modules/flake-module.nix` under `flake.scopes.cache-server.<name>`.
Per the framework's no-untested-code discipline, the new impl
must be exercised against a real fleet before the registration
lands — see how the harmonia + attic-server pair were validated
(both run on lab today; the client side has no idea which one).
