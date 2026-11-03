{ inputs, ... }:
{
  flake.modules.homeManager.herdr-look =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (inputs.self.packages.${pkgs.stdenv.hostPlatform.system}) creeper-otf;
      c = config.lib.stylix.colors.withHashtag;
      home = "${config.xdg.configHome}/herdr-app";

      theme = {
        background = c.base00;
        foreground = c.base05;
        selection = c.base02;
        cursor = c.base05;
        ansi = map (n: c."base0${n}") [
          "0"
          "8"
          "B"
          "A"
          "D"
          "E"
          "C"
          "5"
          "3"
          "8"
          "B"
          "A"
          "D"
          "E"
          "C"
          "7"
        ];
        colors = {
          accent = c.base09;
          accent_foreground = c.base00;
          ring = c.base09;
          working = c.base09;
          blocked = c.base08;
          done = c.base0B;
          idle = c.base03;
        };
      };

      look = {
        theme = "alduin";
        font = "creeper";
        # Creeper has only a 15px bitmap; other sizes draw nothing.
        font_size = 15;
      };
    in
    {
      xdg.configFile = {
        "herdr-app/themes/alduin.json".text = builtins.toJSON theme;
        "herdr-app/fonts/creeper-regular.otf".source =
          "${creeper-otf}/share/fonts/opentype/creeper-regular.otf";
        "herdr-app/fonts/creeper-bold.otf".source = "${creeper-otf}/share/fonts/opentype/creeper-bold.otf";
      };

      # The app writes settings.json from its Settings screen, so merge into it.
      # App screens and toasts draw at sizes creeper lacks, so they keep the default font.
      home.activation.herdrLook = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        if [[ ! -v DRY_RUN ]]; then
          settings=${home}/settings.json
          mkdir -p ${home}
          { cat "$settings" 2>/dev/null || echo '{}'; } \
            | ${lib.getExe pkgs.jq} '. + ${builtins.toJSON look} | del(.ui_font)' > "$settings.new"
          mv "$settings.new" "$settings"
        fi
      '';

      # Shipped mods exist only once the app has run, so clone them at switch time.
      home.activation.herdrCreeper = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        run ${pkgs.python3.interpreter} -I ${./herdr-creeper.py} ${home} ${look.font}
      '';
    };
}
