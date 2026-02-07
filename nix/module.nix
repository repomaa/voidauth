{
  config,
  lib,
  voidauthPackage ? null,
  ...
}:

with lib;

let
  cfg = config.services.voidauth;
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

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/voidauth";
      description = "Data directory for VoidAuth.";
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
      home = cfg.dataDir;
      createHome = true;
      description = "VoidAuth service user";
    };

    users.groups.voidauth = { };

    systemd.tmpfiles.rules = [
      "d '${cfg.dataDir}' 0750 voidauth voidauth -"
      "d '${cfg.dataDir}/config' 0750 voidauth voidauth -"
      "d '${cfg.dataDir}/db' 0750 voidauth voidauth -"
    ];

    systemd.services.voidauth = {
      description = "VoidAuth - Single Sign-On Server";
      after = [
        "network.target"
      ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = "voidauth";
        Group = "voidauth";
        WorkingDirectory = cfg.dataDir;

        EnvironmentFile = mkIf (cfg.environmentFile != null) cfg.environmentFile;

        ExecStart = "${cfg.package}/bin/voidauth serve";

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.dataDir ];
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

        Environment = mapAttrsToList (name: value: "${name}=${toString value}") (
          filterAttrs (n: v: v != null) cfg.settings
        );
      };
    };
  };
}
