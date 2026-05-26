# Router API: GET /status.xml (read), POST /index.xml (commands). No auth.
{
  config,
  lib,
  pkgs,
  fleetHosts,
  ...
}:
let
  routerIp = builtins.head (
    builtins.filter (ip: builtins.elem "msunpv.local" fleetHosts.${ip}) (builtins.attrNames fleetHosts)
  );
in
lib.mkIf config.fleet.server.enable {
  services.home-assistant.config = {
    homeassistant.customize = {
      # MSunPV integration ships state_class=measurement but HA energy dashboard
      # needs total_increasing for daily counters. Upstream issue:
      # github.com/pvergezac/MSunPVIntegration/issues
      "sensor.consommation_jour".state_class = "total_increasing";
      "sensor.injection_jour".state_class = "total_increasing";
      "sensor.production_jour".state_class = "total_increasing";
      "sensor.production_cumul".state_class = "total_increasing";
      "sensor.production_jour_cons".state_class = "total_increasing";
      "sensor.consommation_globale".state_class = "total_increasing";
      "sensor.conso_ballon_jour".state_class = "total_increasing";
      "sensor.conso_radiateur_jour".state_class = "total_increasing";
    };

    # parS position 1: ballon bits 0-1 (1=MANU, 2=AUTO); radiateur bits 2-3 (4=MANU, 8=AUTO).
    shell_command = {
      msunpv_ballon_off = "${pkgs.curl}/bin/curl -s -X POST --data-urlencode 'parS=0;0;0;0;0;0;0;0;' http://${routerIp}/index.xml";
      msunpv_ballon_auto = "${pkgs.curl}/bin/curl -s -X POST --data-urlencode 'parS=2;0;0;0;0;0;0;0;' http://${routerIp}/index.xml";
      msunpv_ballon_manu = "${pkgs.curl}/bin/curl -s -X POST --data-urlencode 'parS=1;0;0;0;0;0;0;0;' http://${routerIp}/index.xml";
    };

    # cmdPos position 1: 0=off, 1=manu (forced), 2=auto. Poll bypasses MSunPV integration.
    command_line = [
      {
        sensor = {
          name = "MSunPV Ballon CmdPos";
          unique_id = "msunpv_ballon_cmdpos_raw";
          command = "${pkgs.curl}/bin/curl -s http://${routerIp}/status.xml | ${pkgs.gnugrep}/bin/grep -oP 'cmdPos>\\K\\d+'";
          scan_interval = 30;
        };
      }
    ];

    input_select.cumulus_mode = {
      name = "Cumulus Mode";
      icon = "mdi:water-boiler";
      options = [
        "Off"
        "Auto"
        "On"
      ];
      initial = "Auto";
    };

    automation = [
      {
        id = "msunpv_cumulus_mode_control";
        alias = "MSunPV Cumulus Mode Control";
        trigger = [
          {
            platform = "state";
            entity_id = "input_select.cumulus_mode";
          }
        ];
        action = [
          {
            choose = [
              {
                conditions = [
                  {
                    condition = "state";
                    entity_id = "input_select.cumulus_mode";
                    state = "Off";
                  }
                ];
                sequence = [ { service = "shell_command.msunpv_ballon_off"; } ];
              }
              {
                conditions = [
                  {
                    condition = "state";
                    entity_id = "input_select.cumulus_mode";
                    state = "Auto";
                  }
                ];
                sequence = [ { service = "shell_command.msunpv_ballon_auto"; } ];
              }
              {
                conditions = [
                  {
                    condition = "state";
                    entity_id = "input_select.cumulus_mode";
                    state = "On";
                  }
                ];
                sequence = [ { service = "shell_command.msunpv_ballon_manu"; } ];
              }
            ];
          }
        ];
      }
      # Mirror router state into the selector for externally-changed mode.
      {
        id = "msunpv_cumulus_mode_sync";
        alias = "MSunPV Cumulus Mode Sync";
        trigger = [
          {
            platform = "state";
            entity_id = "sensor.msunpv_ballon_cmdpos";
          }
        ];
        condition = [
          {
            condition = "not";
            conditions = [
              {
                condition = "state";
                entity_id = "sensor.msunpv_ballon_cmdpos";
                state = "unavailable";
              }
              {
                condition = "state";
                entity_id = "sensor.msunpv_ballon_cmdpos";
                state = "unknown";
              }
            ];
          }
        ];
        action = [
          {
            service = "input_select.select_option";
            target.entity_id = "input_select.cumulus_mode";
            data.option = "{% set v = states('sensor.msunpv_ballon_cmdpos') %}{% if v == '0' %}Off{% elif v == '1' %}On{% else %}Auto{% endif %}";
          }
        ];
      }
    ];
  };
}
