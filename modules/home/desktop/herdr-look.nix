{ config, inputs, ... }:
let
  c = config.flake.lib.base16Scheme;
in
{
  flake.modules.homeManager.herdr-look =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (inputs.self.packages.${pkgs.stdenv.hostPlatform.system}) creeper-otf creeper-ttf;
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
        # Creeper is a 15px font; other sizes draw blank or blurred.
        font_size = 15;
      };

      # macOS draws no bitmap-only fonts, so it gets the traced outlines.
      font =
        if pkgs.stdenv.hostPlatform.isDarwin then
          {
            dir = "${creeper-ttf}/share/fonts/truetype";
            ext = "ttf";
          }
        else
          {
            dir = "${creeper-otf}/share/fonts/opentype";
            ext = "otf";
          };
      fontFile = style: {
        name = "herdr-app/fonts/creeper-${style}.${font.ext}";
        value.source = "${font.dir}/creeper-${style}.${font.ext}";
      };
    in
    {
      # The home layout, its mods' prefix and the sidebar text, for modules that build on them.
      lib.herdr = {
        home = "creeper";
        prefix = "creeper-";
        text = {
          inherit (look) font;
          size = look.font_size;
        };
      };

      xdg.configFile = {
        "herdr-app/themes/alduin.json".text = builtins.toJSON theme;
      }
      // lib.listToAttrs (
        map fontFile [
          "regular"
          "bold"
        ]
      );

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
