# Coordinator meta-scope. Imports the full coordinator bundle and
# defaults their enable flags on when nixfleet.coordinator.enable is
# set. Individual sub-scope configuration stays at the sub-scope's own
# option path — this module does not pass options through.
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

    # Bundle C (nixfleet#41): the issuance CA keyslot lives on every
    # coordinator host alongside the legacy ciReleaseKey (provisioned
    # via `nixfleet.keyslots.tpm.handle = "0x81010001"` set in
    # flake.nix). Distinct persistent handle, secure-by-default PCR 0
    # policy. The systemd oneshot
    # nixfleet-tpm-keyslot-provision-issuanceCA exports
    # /var/lib/nixfleet-tpm-keyslot/issuanceCA/pubkey.raw at first
    # boot; the operator then runs `nixfleet-cp-bootstrap` to mint
    # the offline fleet root + issuance CA cert from that pubkey.
    nixfleet.keyslots.tpm.keys.issuanceCA = {
      handle = "0x81010002";
      algorithm = "ecdsa-p256";
      pcrPolicy = [ "0" ];
    };
  };
}
