# Server base — hardening and power management for headless servers.
{
  config,
  lib,
  ...
}:
{
  config = lib.mkIf config.fleet.server.enable {
    # Prevent suspend/hibernate — servers must stay online
    systemd.targets.sleep.enable = false;
    systemd.targets.suspend.enable = false;
    systemd.targets.hibernate.enable = false;
    systemd.targets.hybrid-sleep.enable = false;

    # Ignore power key (prevent accidental shutdown from brief press)
    services.logind.settings.Login = {
      HandlePowerKey = "ignore";
      HandleSuspendKey = "ignore";
      HandleHibernateKey = "ignore";
      HandleLidSwitch = "ignore";
      IdleAction = "ignore";
    };
  };
}
