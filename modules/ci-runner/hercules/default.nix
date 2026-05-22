# Hercules CI agent driver.
#
# Sibling of `forgejo-actions` under the `nixfleet.ciRunner.*`
# umbrella. Self-contained: own option subnamespace
# (`nixfleet.ciRunner.hercules.*`), own systemd unit. Coexists
# fine with the forgejo-actions sibling — different services,
# different option subtrees.
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixfleet.ciRunner.hercules;
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.agentTokenFile != null;
        message = "nixfleet.ciRunner.hercules.enable requires hercules.agentTokenFile.";
      }
    ];

    services.hercules-ci-agent = {
      enable = true;
      settings = {
        inherit (cfg) concurrentTasks;
      };
    };

    systemd.services.hercules-ci-agent.serviceConfig = {
      LoadCredential = "agent-token:${cfg.agentTokenFile}";
      Environment = [ "HERCULES_CI_AGENT_TOKEN_FILE=%d/agent-token" ];
    };
  };
}
