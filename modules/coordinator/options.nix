# Coordinator meta-scope — option declarations.
#
# Thin facade over the individual scopes (forge, ci-runner,
# reverse-proxy, backup-server, tpm-keyslot). Setting
# nixfleet.coordinator.enable = true cascades mkDefault enable flags to
# the sub-scopes; the consumer still configures each sub-scope through
# its own option path (nixfleet.forge.*, nixfleet.ciRunner.*, ...).
{ lib, ... }:
{
  options.nixfleet.coordinator = {
    enable = lib.mkEnableOption ''
      This host is a fleet coordinator. Sets forge /
      ci-runner / reverse-proxy / backup-server / tpm-keyslot enable
      flags to lib.mkDefault true and acts as a discovery flag for
      scopes that want to adjust behaviour when running on a coordinator
      (for instance, the backup client scope skipping itself).
    '';

    domain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "lab.internal";
      description = "Base internal domain. Informational — individual scopes consume it to derive their own FQDNs.";
    };
  };
}
