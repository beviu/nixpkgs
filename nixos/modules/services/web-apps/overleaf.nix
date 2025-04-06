{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.services.overleaf;

  overleafServices = [
    "chat"
    "clsi"
    "contacts"
    "docstore"
    "document-updater"
    "filestore"
    "history-v1"
    "notifications"
    "project-history"
    "real-time"
    "web"
  ];

  secretsDirectory = "/var/lib/overleaf/secrets";

in
{
  meta.maintainers = with maintainers; [
    julienmalka
    camillemndn
  ];

  options.services.overleaf = {
    enable = mkEnableOption "Overleaf";

    hostname = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "overleaf.org";
      description = "This enable a default nginx reverse proxy configuration.";
    };

    redis = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Start a Redis server for Overleaf.";
      };

      host = mkOption {
        type = types.str;
        default = "localhost";
        description = "Redis host.";
      };

      port = mkOption {
        type = types.port;
        default = 6379;
        description = "Redis port.";
      };
    };

    mongodb = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "MongoDB is enabled by default.";
      };

      package = mkOption {
        type = types.package;
        example = literalExpression "pkgs.ferretdb";
        default = pkgs.ferretdb;
        defaultText = "pkgs.ferretdb";
        description = "MongoDB/FerretDB package to use.";
      };
    };

    texlivePackage = mkOption {
      type = types.package;
      default = pkgs.texliveMedium;
      defaultText = literalExpression "pkgs.textliveMedium";
      example = literalExpression "pkgs.texliveFull";
      description = ''
        The package for TeX Live. See
        <https://search.nixos.org/packages?query=texlive>
        for available options.
      '';
    };

    settings = mkOption {
      type = types.submodule { freeformType = with types; attrsOf str; };
      default = { };
      example = {
        WEB_HOST = "localhost";
        WEB_PORT = "3032";
        GRACEFUL_SHUTDOWN_DELAY = "0";
        OVERLEAF_SITE_URL = "https://overleaf.example.org";
        OVERLEAF_ADMIN_EMAIL = "overleaf@example.org";
        OVERLEAF_SITE_LANGUAGE = "fr";
        OVERLEAF_APP_NAME = "My self-hosted Overleaf instance";
        OVERLEAF_EMAIL_FROM_ADDRESS = "overleaf@example.org";
        OVERLEAF_EMAIL_SMTP_HOST = "mail.example.org";
        OVERLEAF_EMAIL_SMTP_PORT = "587";
        OVERLEAF_EMAIL_SMTP_SECURE = "true";
        OVERLEAF_EMAIL_SMTP_USER = "overleaf";
        OVERLEAF_GITBRIDGE_PORT = "3029";
        ADMIN_PRIVILEGE_AVAILABLE = "true";
      };
      description = ''
        Additional configuration for Overleaf, see
        <https://github.com/overleaf/overleaf/blob/main/server-ce/config/settings.js>
        for supported values.
      '';
    };

    secrets = {
      webApiPasswordFile = mkOption {
        type = types.str;
        default = "${secretsDirectory}/web-api-password";
        description = ''
          Path to a file that contains the web API password.
        '';
      };

      historyApiPasswordFile = mkOption {
        type = types.str;
        default = "${secretsDirectory}/history-api-password";
        description = ''
          Path to a file that contains the history API password.
        '';
      };

      sessionKeyFile = mkOption {
        type = types.str;
        default = "${secretsDirectory}/session-key";
        description = ''
          Path to the file that contains the key used to sign session cookies.
        '';
      };

      jwtKeyFile = mkOption {
        type = types.str;
        default = "${secretsDirectory}/jwt-key";
        description = ''
          Path to the file that contains the JWT key.
        '';
      };
    };

    path = mkOption {
      type = with types; listOf package;
      default = [ ];
      example = literalExpression "with pkgs; [ qpdf ]";
      description = ''
        Additional packages to place in the path of the Overleaf services.
      '';
    };

    latexmkrc = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Extra contents appended to the LaTeX configuration file,
        .latexmkrc.
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = cfg.redis.enable -> cfg.redis.host == "localhost";
          message = "Local Redis server must be disabled when the Redis hostname is set.";
        }
      ];

      services.overleaf.settings = {
        NODE_ENV = "production";
        NODE_CONFIG_DIR = "${pkgs.overleaf}/share/services/history-v1/config";
        OVERLEAF_CONFIG = "${pkgs.overleaf}/share/server-ce/config/settings.js";
        DATA_DIR = mkDefault "/var/lib/overleaf";
        OVERLEAF_MONGO_URL = mkDefault "mongodb://127.0.0.1:27017/overleaf";
        OVERLEAF_REDIS_HOST = cfg.redis.host;
        OVERLEAF_REDIS_PORT = builtins.toString cfg.redis.port;
        WEB_PORT = mkDefault "3000";
        WEB_API_USER = mkDefault "overleaf";
        GRACEFUL_SHUTDOWN_DELAY = mkDefault "0";
        OVERLEAF_FPH_DISPLAY_NEW_PROJECTS = mkDefault "true";
      };

      systemd.targets.overleaf.requires = map (service: "overleaf-${service}.service") overleafServices;

      systemd.services =
        let
          secretsToGenerate = builtins.map (lib.strings.removePrefix "${secretsDirectory}/") (
            builtins.filter (lib.strings.hasPrefix "${secretsDirectory}/") (builtins.attrValues cfg.secrets)
          );
          deps =
            builtins.map (name: "overleaf-generate-secret@${name}.service") secretsToGenerate
            ++ lib.optionals cfg.redis.enable [ "redis-overleaf.service" ];
          mkServiceUnit = service: {
            name = "overleaf-${service}";
            value = {
              description = "Overleaf ${service}";
              wantedBy = [
                "overleaf.target"
                "multi-user.target"
              ];
              after = deps;
              wants = deps;
              environment = cfg.settings;
              path =
                with pkgs;
                [
                  cfg.texlivePackage
                  qpdf
                ]
                ++ cfg.path;
              serviceConfig = {
                Type = "simple";
                ExecStart = pkgs.writeShellScript "overleaf-${service}" ''
                  export WEB_API_PASSWORD="$(< "$CREDENTIALS_DIRECTORY/webApiPasswordFile")"
                  export V1_HISTORY_PASSWORD="$(< "$CREDENTIALS_DIRECTORY/historyApiPasswordFile")"
                  export STAGING_PASSWORD="$(< "$CREDENTIALS_DIRECTORY/historyApiPasswordFile")"
                  export OVERLEAF_SESSION_SECRET="$(< "$CREDENTIALS_DIRECTORY/sessionKeyFile")"
                  export OT_JWT_AUTH_KEY="$(< "$CREDENTIALS_DIRECTORY/jwtKeyFile")"

                  # This softlinks the LaTeX configuration files to the home of Overleaf:
                  ${optionalString (cfg.latexmkrc != "") "ln -sf ${cfg.latexmkrc} /var/lib/overleaf/.latexmkrc"}

                  exec ${pkgs.overleaf}/bin/overleaf-${service}
                '';
                StateDirectory = "overleaf";
                WorkingDirectory = "/var/lib/overleaf";
                User = "overleaf";
                LoadCredential = lib.mapAttrsToList (name: value: name + ":" + value) cfg.secrets;
                ProtectHome = true;
                ProtectSystem = "strict";
                NoNewPrivileges = true;
                PrivateDevices = true;
                PrivateTmp = true;
                ProtectHostname = true;
                ProtectClock = true;
                ProtectKernelTunables = true;
                ProtectKernelModules = true;
                ProtectKernelLogs = true;
                ProtectControlGroups = true;
                Restart = "on-failure";
              };
            };
          };
        in
        builtins.listToAttrs (builtins.map mkServiceUnit overleafServices)
        // {
          "overleaf-generate-secret@" = {
            description = "Generate secret %i for Overleaf";
            script = ''
              if [ ! -f "secrets/$SECRET" ]; then
                mkdir -p secrets
                head -c 32 /dev/random | base64 --wrap 0 | head -c -1 > "secrets/$SECRET"
              fi
            '';
            environment.SECRET = "%i";
            serviceConfig = {
              Type = "oneshot";
              WorkingDirectory = "/var/lib/overleaf";
              User = "overleaf";
              UMask = "0077";
            };
          };
        };

      users.users.overleaf = {
        isSystemUser = true;
        group = "overleaf";
        home = "/var/lib/overleaf";
        createHome = true;
      };

      users.groups.overleaf = { };

      services.nginx = mkIf (isString cfg.hostname) {
        enable = true;
        recommendedOptimisation = mkDefault true;
        recommendedGzipSettings = mkDefault true;

        virtualHosts."${cfg.hostname}" = {
          locations."/" = {
            proxyPass = "http://localhost:${cfg.settings.WEB_PORT}";
            proxyWebsockets = true;
          };
          locations."/socket.io" = {
            proxyPass = "http://localhost:3026";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_read_timeout 10m;
              proxy_send_timeout 10m;
            '';
          };
        };
      };

      services.redis.servers.overleaf = mkIf cfg.redis.enable {
        enable = true;
        user = "overleaf";
        port = cfg.redis.port;
        unixSocket = null;
      };
    }

    (mkIf (cfg.mongodb.enable && cfg.mongodb.package.pname == "mongodb") {
      services.mongodb = {
        enable = true;
        inherit (cfg.mongodb) package;
      };
    })

    (mkIf (cfg.mongodb.enable && cfg.mongodb.package.pname == "ferretdb") {
      services.ferretdb = {
        enable = true;
        inherit (cfg.mongodb) package;
      };
      systemd.services.ferretdb.serviceConfig.ExecStart =
        mkForce "${cfg.mongodb.package}/bin/ferretdb --postgresql-url=\"postgres://localhost/ferretdb?host=/run/postgresql\"";
      systemd.services.postgresql.environment.LC_ALL = "en_US.UTF-8";

      users.users.ferretdb = {
        isSystemUser = true;
        group = "ferretdb";
        home = "/var/lib/ferretdb";
        createHome = true;
      };

      users.groups.ferretdb = { };

      services.postgresql = {
        enable = true;
        ensureDatabases = [ "ferretdb" ];
        ensureUsers = [
          {
            name = "ferretdb";
            ensureDBOwnership = true;
          }
        ];
      };
    })
  ]);
}
