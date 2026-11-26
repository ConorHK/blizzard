topLevel@{ inputs, ... }:
{
  flake.wrappers.eww =
    {
      config,
      lib,
      pkgs,
      wlib,
      ...
    }:
    let
      inherit (inputs.self.packages.${pkgs.stdenv.hostPlatform.system}) ws-thumbs;
      alacritty = topLevel.config.flake.wrappers.alacritty.wrap { inherit pkgs; };
      jujutsu = topLevel.config.flake.wrappers.jujutsu.wrap { inherit pkgs; };

      script =
        name: runtimeInputs:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = [
            pkgs.coreutils
            pkgs.jq
          ]
          ++ runtimeInputs;
          text = builtins.readFile ./scripts/${name}.sh;
        };

      check-backups = pkgs.writeShellApplication {
        name = "check-backups";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.jq
          pkgs.systemd
        ];
        text = builtins.readFile ./scripts/check-backups.sh;
      };

      check-flake-updates = pkgs.writeShellApplication {
        name = "check-flake-updates";
        runtimeInputs = [
          jujutsu
          pkgs.coreutils
          pkgs.git
          pkgs.openssh
        ];
        # Every path must print JSON and exit 0, so errors are handled by hand.
        bashOptions = [ ];
        text = builtins.readFile ./scripts/check-flake-updates.sh;
      };

      scripts = [
        (script "sidebar-workspaces" [ pkgs.socat ])
        (script "sidebar-thumb" [
          pkgs.eww
          pkgs.util-linux
          ws-thumbs
        ])
        (script "sidebar-focus" [ ])
        (script "sidebar-volume" [
          pkgs.gawk
          pkgs.gnused
          pkgs.pulseaudio
          pkgs.wireplumber
        ])
        (script "sidebar-bluetooth" [
          pkgs.bluez
          pkgs.gnused
        ])
        (script "sidebar-network" [
          pkgs.gawk
          pkgs.gnugrep
          pkgs.networkmanager
        ])
        (script "sidebar-failed" [
          pkgs.gnused
          pkgs.systemd
        ])
        (script "sidebar-privacy" [ pkgs.pipewire ])
        (script "sidebar-battery" [ ])
        (script "sidebar-run" [
          alacritty
          pkgs.blueman
          check-backups
          check-flake-updates
          jujutsu
          pkgs.networkmanager
          pkgs.pwvucontrol
          pkgs.systemd
          pkgs.util-linux
          pkgs.wireplumber
        ])
      ];

      hostModules = {
        battery = ''(module :name "battery" :data battery)'';
      };

      hostYuck = pkgs.writeText "host.yuck" ''
        (defwidget host-modules []
          (box :orientation "v" :space-evenly false :spacing 5
            ${lib.concatMapStrings (m: hostModules.${m}) config.extraModules}))
      '';

      configDir = pkgs.runCommand "eww-config" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
        mkdir $out
        cp ${./config/eww.yuck} $out/eww.yuck
        cp ${./config/eww.css} $out/eww.css
        cp ${hostYuck} $out/host.yuck
        # The thumbnail before the first capture.
        magick -size 1x1 xc:none $out/blank.png
      '';
    in
    {
      imports = [ wlib.modules.default ];

      options = {
        extraModules = lib.mkOption {
          type = with lib.types; listOf (enum (lib.attrNames hostModules));
          default = [ ];
          description = "Sidebar modules placed below volume.";
        };
        output = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
          example = "DP-1";
          description = "Output that shows the bar. Unset shows it on every output.";
        };
      };

      config = {
        package = pkgs.eww;
        flags."--config" = "${configDir}";
        runtimePkgs = scripts ++ [ pkgs.wireplumber ];
      };
    };

  perSystem =
    { pkgs, ... }:
    {
      wrappers.packages.eww = !pkgs.stdenv.hostPlatform.isLinux;
    };
}
