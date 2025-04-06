{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

let
  cfg = config.services.autologin;
  tty = "tty${builtins.toString cfg.vt}";
in
{
  options.services.autologin = {
    enable = lib.mkEnableOption "automatic login without a display manager";

    package = lib.mkPackageOption pkgs "autologin" { };

    user = lib.mkOption {
      type = lib.types.str;
      description = ''
        User to be used for the automatic login.
      '';
    };

    command = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = ''
        Command to execute in the user session.
      '';
    };

    vt = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = ''
        The virtual console (tty) that autologin should use. This option also disables getty on that tty.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.services.displayManager.enable;
        message = "services.autologin.enable conflicts with services.displayManager.enable";
      }
    ];

    systemd.services.autologin = {
      description = "Automatic login";

      after = [
        "systemd-user-sessions.service"
        "plymouth-quit-wait.service"
        "getty@${tty}.service"
      ];
      conflicts = [ "getty@${tty}.service" ];

      wantedBy = [ "graphical.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${lib.getExe cfg.package} ${utils.escapeSystemdExecArg cfg.user} ${utils.escapeSystemdExecArgs cfg.command}";
        Restart = "always";
        RestartSec = "0";
        TTYPath = "/dev/${tty}";
      };

      restartIfChanged = false;

      aliases = [ "display-manager.service" ];
    };

    systemd.defaultUnit = "graphical.target";

    # This prevents nixos-rebuild from killing autologin by activating getty again.
    systemd.services."autovt@${tty}".enable = false;

    security.pam.services.autologin = {
      allowNullPassword = true;
      startSession = true;
    };
  };

  meta.maintainers = with lib.maintainers; [ beviu ];
}
