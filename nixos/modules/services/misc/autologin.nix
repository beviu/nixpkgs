{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

let
  cfg = config.services.autologin;
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
      type = lib.types.str;
      description = ''
        Command to execute in the user session.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.services.displayManager.enable;
        message = "services.autologin conflicts with services.displayManager";
      }
    ];

    systemd.services.autologin = {
      description = "Automatic login";

      after = [
        "systemd-user-sessions.service"
        "plymouth-quit-wait.service"
        "getty@tty1.service"
      ];
      conflicts = [ "getty@tty1.service" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${lib.getExe cfg.package} ${utils.escapeSystemdExecArg cfg.user} ${utils.escapeSystemdExecArg cfg.command}";
      };

      aliases = [ "display-manager.service" ];
    };

    security.pam.services.autologin = {
      allowNullPassword = true;
      startSession = true;
    };
  };

  meta.maintainers = with lib.maintainers; [ beviu ];
}
