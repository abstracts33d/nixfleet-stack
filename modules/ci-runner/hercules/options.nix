# Hercules CI agent — option declarations.
{ lib, ... }:
let
  inherit (lib) types;
in
{
  options.nixfleet.ciRunner.hercules = {
    enable = lib.mkEnableOption "Hercules CI agent (Nix-native)";

    agentTokenFile = lib.mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/run/secrets/hercules-agent-token";
      description = "Path to the Hercules agent token file. Required when hercules.enable is true.";
    };

    nixBinaryCaches = lib.mkOption {
      type = types.str;
      default = "";
      example = ''{"substituters":["https://cache.example.com"],"trusted-public-keys":["..."]}'';
      description = "Optional JSON string describing extra substituters the agent trusts.";
    };

    concurrentTasks = lib.mkOption {
      type = types.int;
      default = 4;
      description = "Maximum concurrent Nix builds.";
    };
  };
}
