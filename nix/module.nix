{
  config,
  lib,
  voidauthPackage ? null,
  ...
}:

with lib;

let
  cfg = config.services.voidauth;
  dataDir = "/var/lib/voidauth";
in
{
  options.services.voidauth = {
    enable = mkEnableOption "VoidAuth - Single Sign-On for Your Self-Hosted Universe";

    package = mkOption {
      type = types.package;
      default = voidauthPackage;
      defaultText = literalExpression "voidauthPackage";
      description = "The VoidAuth package to use.";
    };

    settings = mkOption {
      type = types.attrsOf (
        types.oneOf [
          types.str
          types.int
          types.bool
          (types.nullOr types.str)
        ]
      );
      default = { };
      description = "VoidAuth environment configuration. See documentation for available options.";
      example = literalExpression ''
        {
          APP_URL = "https://auth.example.com";
          APP_PORT = 3000;
          STORAGE_KEY = "your-32-character-secret-key-here";
        }
      '';
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Optional path to environment file for secrets.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.settings ? APP_URL || cfg.environmentFile != null;
        message = "services.voidauth.settings.APP_URL must be set or environmentFile must be provided";
      }
      {
        assertion = cfg.settings ? STORAGE_KEY || cfg.environmentFile != null;
        message = "services.voidauth.settings.STORAGE_KEY must be set or environmentFile must be provided";
      }
    ];

    users.users.voidauth = {
      isSystemUser = true;
      group = "voidauth";
      description = "VoidAuth service user";
    };

    users.groups.voidauth = { };

    # Create writable state directories
    systemd.tmpfiles.rules =
      lib.map (dir: "d ${dataDir}/${dir} 0755 voidauth voidauth -") [
        "theme"
        "config"
        "config/email_templates"
        "migrations"
        "frontend"
        "node_modules"
        "default_email_templates"
      ]
      ++ lib.optional ((cfg.settings.DB_TYPE or "postgres") == "sqlite") "db";

    systemd.services.voidauth = {
      description = "VoidAuth - Single Sign-On Server";
      after = [
        "network.target"
      ];
      wantedBy = [ "multi-user.target" ];

      preStart = ''
        # Copy theme files on first start (custom.css is preserved)
        if [ ! -f "${dataDir}/theme/custom.css" ]; then
          cp -r ${cfg.package}/share/voidauth/theme/. "${dataDir}/theme/"
          chmod -R 644 "${dataDir}/theme"/*
        fi
      '';

      serviceConfig = {
        Type = "simple";
        User = "voidauth";
        Group = "voidauth";

        # Use StateDirectory for automatic /var/lib/voidauth creation
        StateDirectory = "voidauth";
        WorkingDirectory = "%S/voidauth";

        # Bind read-only directories from nix store
        BindReadOnlyPaths = lib.map (dir: "${cfg.package}/share/voidauth/${dir}:${dataDir}/${dir}") [
          "migrations"
          "frontend"
          "node_modules"
          "default_email_templates"
        ];

        EnvironmentFile = mkIf (cfg.environmentFile != null) cfg.environmentFile;

        ExecStart = "${cfg.package}/bin/voidauth serve";

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = lib.optional (cfg.settings.DB_SOCKET_PATH != null) cfg.settings.DB_SOCKET_PATH;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        RestrictRealtime = true;
        RestrictNamespaces = true;
        LockPersonality = true;
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
        ];

        Restart = "on-failure";
        RestartSec = 5;

        Environment =
          mapAttrsToList (name: value: "${name}=${toString value}") (
            filterAttrs (n: v: v != null) cfg.settings
          )
          ++ [
            "FRONTEND_PATH=${cfg.package}/share/voidauth/frontend"
          ];
      };
    };
  };
}
