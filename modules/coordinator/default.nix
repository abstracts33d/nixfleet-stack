# Meta-scope: imports the coordinator bundle and defaults their enable flags
# when nixfleet.coordinator.enable is set. Configure sub-scopes at their own
# option path; this module does not pass options through.
{
  config,
  inputs,
  lib,
  ...
}:
let
  cfg = config.nixfleet.coordinator;
in
{
  imports = [
    ./options.nix
    ../forge/forgejo
    ../ci-runner/forgejo-actions
    ../reverse-proxy
    ../backup-server
    inputs.nixfleet.scopes.keyslots.tpm
  ];

  config = lib.mkIf cfg.enable {
    nixfleet.forge.enable = lib.mkDefault true;
    nixfleet.ciRunner.forgejoActions.enable = lib.mkDefault true;
    nixfleet.reverseProxy.enable = lib.mkDefault true;
    nixfleet.backupServer.enable = lib.mkDefault true;
    nixfleet.keyslots.tpm.enable = lib.mkDefault true;

    # Bundle C (nixfleet#41): issuance CA keyslot, distinct handle from the
    # legacy ciReleaseKey (0x81010001 in flake.nix), PCR 0 policy.
    # nixfleet-tpm-keyslot-provision-issuanceCA exports
    # /var/lib/nixfleet-tpm-keyslot/issuanceCA/pubkey.raw at first boot;
    # operator then runs `nixfleet-cp-bootstrap`.
    nixfleet.keyslots.tpm.keys.issuanceCA = {
      handle = "0x81010002";
      algorithm = "ecdsa-p256";
      pcrPolicy = [ "0" ];
    };
  };
}
