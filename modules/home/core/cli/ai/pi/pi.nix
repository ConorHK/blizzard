{
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
      # Prebuilt binary; patchelf corrupts bun executables.
      # NixOS hosts need programs.nix-ld.
      pi-bin = pkgs.stdenvNoCC.mkDerivation rec {
        pname = "pi";
        version = "0.85.1";
        src = pkgs.fetchurl {
          url = "https://github.com/badlogic/pi-mono/releases/download/v${version}/pi-linux-x64.tar.gz";
          hash = "sha256-SU5Jj0fXTSH0CzOG9qXpIaPUlTGhacq1W72soOof4lo=";
        };
        dontUnpack = true;
        dontFixup = true;
        # Full tree: pi loads themes beside the binary.
        installPhase = ''
          mkdir -p $out/libexec $out/bin
          tar xzf $src -C $out/libexec
          chmod +x $out/libexec/pi/pi
          ln -s $out/libexec/pi/pi $out/bin/pi
        '';
        meta = {
          mainProgram = "pi";
          platforms = [ "x86_64-linux" ];
        };
      };
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
      # Same policy script Claude Code's hook runs.
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
      # Allowlist jail: OS read-only, home hidden.
      # Workspace and ~/.pi/agent stay writable.
      jailScript = pkgs.writeShellApplication {
        name = "pi-jail";
        runtimeInputs = [
          pkgs.bubblewrap
          pkgs.coreutils
        ];
        # Tildes are expanded by expand() below.
        excludeShellChecks = [ "SC2088" ];
        text = ''
          home=$(readlink -f "$HOME")
          cwd=$(readlink -f "$PWD")
          # Binding home rw would defeat the tmpfs.
          case "$home" in
            "$cwd" | "$cwd"/*)
              echo "pi-jail: workspace contains home; refusing" >&2
              exit 1
              ;;
          esac
          args=(
            --ro-bind / /
            --proc /proc
            --dev /dev
            --tmpfs /tmp
            --tmpfs "$home"
            --unshare-all
            --die-with-parent
          )
          ${lib.optionalString cfg.jail.network "args+=(--share-net)"}
          ${lib.optionalString cfg.jail.newSession "args+=(--new-session)"}
          expand() {
            local p="$1"
            if [[ "$p" == "~/"* ]]; then p="$HOME/''${p#"~/"}"; fi
            printf '%s' "$p"
          }
          # Resolved source, canonical-parent dest: bwrap
          # cannot mount through symlinks.
          bind() {
            local flag="$1" p="$2" src dest
            if [ ! -e "$p" ]; then
              echo "pi-jail: skipping missing $p" >&2
              return 0
            fi
            src=$(readlink -f "$p")
            dest="$(readlink -f "$(dirname "$p")")/$(basename "$p")"
            args+=("$flag" "$src" "$dest")
          }
          bind --bind "$cwd"
          bind --bind "$HOME/.pi/agent"
          # A session cannot rewrite next session's guard.
          bind --ro-bind "$HOME/.pi/agent/extensions"
          bind --ro-bind "$HOME/.nix-profile"
          allow=(${lib.escapeShellArgs cfg.jail.allow})
          for p in "''${allow[@]}"; do bind --bind "$(expand "$p")"; done
          ro=(${lib.escapeShellArgs cfg.jail.readOnly})
          for p in "''${ro[@]}"; do bind --ro-bind "$(expand "$p")"; done
          extra=(${lib.escapeShellArgs cfg.jail.extraBwrapArgs})
          if [ "''${#extra[@]}" -gt 0 ]; then args+=("''${extra[@]}"); fi
          exec bwrap "''${args[@]}" -- ${lib.getExe piPackage} "$@"
        '';
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
          default = pi-bin;
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
        programs.pi.settings = {
          enableInstallTelemetry = lib.mkDefault false;
          theme = lib.mkDefault "dark";
        };
        home = {
          packages = [ piPackage ] ++ lib.optional cfg.jail.enable jailScript;
          file =
            lib.mapAttrs' (
              name: src: lib.nameValuePair ".pi/agent/extensions/${name}.ts" { source = src; }
            ) cfg.extensions
            // lib.mapAttrs' (
              name: src: lib.nameValuePair ".pi/agent/extensions/${name}" { source = src; }
            ) cfg.extensionDirs
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
}
