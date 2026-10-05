topLevel: {
  flake.modules.homeManager.pi =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.pi;
      settingsFormat = pkgs.formats.json { };
      piPackage =
        if cfg.env == { } then
          cfg.package
        else
          pkgs.writeShellScriptBin "pi" ''
            ${lib.concatStringsSep "\n" (
              lib.mapAttrsToList (n: v: "export ${n}=${lib.escapeShellArg v}") cfg.env
            )}
            exec ${lib.getExe cfg.package} "$@"
          '';
      defaultGuard = pkgs.writeShellApplication {
        name = "pi-bash-guard";
        runtimeInputs = [
          pkgs.jq
          pkgs.git
        ];
        text = builtins.readFile ../auto-mode-guard.sh;
      };
      guardExtension = pkgs.writeText "pi-guard.ts" (
        builtins.replaceStrings [ "@guard@" ] [ (lib.getExe cfg.guard.script) ] (
          builtins.readFile ./guard.ts
        )
      );
      jailScript = topLevel.config.flake.lib.mkPiJail pkgs {
        package = piPackage;
        inherit (cfg.jail)
          network
          hostLoopback
          newSession
          allow
          readOnly
          extraBwrapArgs
          ;
      };
      settingsFile = settingsFormat.generate "pi-settings.json" cfg.settings;
      modelsFile = settingsFormat.generate "pi-models.json" cfg.models;
      # attrValues sorts by name, so order is stable.
      rulesFile = pkgs.concatText "pi-agents.md" (lib.attrValues cfg.rules);
    in
    {
      options.programs.pi = {
        package = lib.mkOption {
          type = lib.types.package;
          default = topLevel.inputs.pi.packages.${pkgs.stdenv.hostPlatform.system}.default;
          description = "pi coding agent package.";
        };
        env = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Environment variables exported before pi runs.";
        };
        settings = lib.mkOption {
          inherit (settingsFormat) type;
          default = { };
          description = "Contents of ~/.pi/agent/settings.json.";
        };
        models = lib.mkOption {
          inherit (settingsFormat) type;
          default = { };
          description = "Contents of ~/.pi/agent/models.json (custom providers).";
        };
        extensions = lib.mkOption {
          type = lib.types.attrsOf lib.types.path;
          default = { };
          description = "Extra extensions installed to ~/.pi/agent/extensions/<name>.ts. The name guard is reserved.";
        };
        extensionDirs = lib.mkOption {
          type = lib.types.attrsOf lib.types.path;
          default = { };
          description = "Extra multi-file extensions installed to ~/.pi/agent/extensions/<name>/.";
        };
        rules = lib.mkOption {
          type = lib.types.attrsOf lib.types.path;
          default = { };
          description = "Instruction files concatenated into ~/.pi/agent/AGENTS.md.";
        };
        themes = lib.mkOption {
          type = lib.types.attrsOf lib.types.path;
          default = { };
          description = "Theme files installed to ~/.pi/agent/themes/<name>.json.";
        };
        guard = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Block guarded bash commands via a tool_call extension.";
          };
          script = lib.mkOption {
            type = lib.types.package;
            default = defaultGuard;
            description = "Guard reading PreToolUse JSON on stdin, deny JSON on stdout.";
          };
        };
        jail = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Install pi-jail, a bubblewrap wrapper around pi.";
          };
          allow = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Extra paths bound writable inside the jail.";
          };
          readOnly = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Extra paths bound read-only inside the jail.";
          };
          network = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether the jail keeps network access.";
          };
          hostLoopback = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Let the jail reach services on host loopback.";
          };
          newSession = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Detach the terminal, blocking TIOCSTI keystroke injection.";
          };
          extraBwrapArgs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Extra raw bwrap arguments.";
          };
        };
      };

      config = {
        programs.pi = {
          settings = {
            enableInstallTelemetry = lib.mkDefault false;
            theme = lib.mkDefault "blizzard";
            tuiMode = lib.mkDefault "regular";
          };
          themes.blizzard = ./themes/blizzard.json;
        };
        home = {
          packages = [
            piPackage
            pkgs.nixd
          ]
          ++ lib.optional cfg.jail.enable jailScript;
          file =
            lib.mapAttrs' (
              name: src: lib.nameValuePair ".pi/agent/extensions/${name}.ts" { source = src; }
            ) cfg.extensions
            // lib.mapAttrs' (
              name: src: lib.nameValuePair ".pi/agent/extensions/${name}" { source = src; }
            ) cfg.extensionDirs
            // lib.mapAttrs' (
              name: src: lib.nameValuePair ".pi/agent/themes/${name}.json" { source = src; }
            ) cfg.themes
            // lib.optionalAttrs cfg.guard.enable {
              ".pi/agent/extensions/guard.ts".source = guardExtension;
            }
            // lib.optionalAttrs (cfg.models != { }) {
              ".pi/agent/models.json".source = modelsFile;
            };
          # Writable copies: pi rewrites settings.json.
          activation.piSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            run install -Dm644 ${settingsFile} ${config.home.homeDirectory}/.pi/agent/settings.json
            ${
              if cfg.rules != { } then
                "run install -Dm644 ${rulesFile} ${config.home.homeDirectory}/.pi/agent/AGENTS.md"
              else
                # No stale AGENTS.md when rules empty.
                "run rm -f ${config.home.homeDirectory}/.pi/agent/AGENTS.md"
            }
          '';
        };
      };
    };

  flake.modules.nixos.pi =
    { config, ... }:
    {
      # pi is a prebuilt binary; it needs the nix-ld loader.
      programs.nix-ld.enable = true;

      # pi-jail's daemon socket: same store, no trust.
      systemd.sockets.pi-nix-daemon = {
        description = "Untrusted Nix daemon socket for pi-jail";
        wantedBy = [ "sockets.target" ];
        socketConfig = {
          ListenStream = "/run/pi-nix-daemon/socket";
          SocketMode = "0666";
        };
      };

      systemd.services.pi-nix-daemon = {
        description = "Proxy pi-jail to the Nix daemon as an untrusted user";
        requires = [ "pi-nix-daemon.socket" ];
        after = [ "pi-nix-daemon.socket" ];
        serviceConfig = {
          ExecStart = "${config.systemd.package}/lib/systemd/systemd-socket-proxyd /nix/var/nix/daemon-socket/socket";
          DynamicUser = true;
          PrivateNetwork = true;
          RestrictAddressFamilies = [ "AF_UNIX" ];
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          NoNewPrivileges = true;
        };
      };
    };
}
