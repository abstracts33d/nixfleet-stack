{
  config,
  lib,
  ...
}:
{
  config = lib.mkIf config.fleet.server.enable {
    systemd.targets.sleep.enable = false;
    systemd.targets.suspend.enable = false;
    systemd.targets.hibernate.enable = false;
    systemd.targets.hybrid-sleep.enable = false;

    services.logind.settings.Login = {
      HandlePowerKey = "ignore";
      HandleSuspendKey = "ignore";
      HandleHibernateKey = "ignore";
      HandleLidSwitch = "ignore";
      IdleAction = "ignore";
    };
  };
}
