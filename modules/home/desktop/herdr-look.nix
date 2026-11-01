{ inputs, ... }:
{
  flake.modules.homeManager.herdr-app =
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
        # The creeper strike is 15px; other sizes draw nothing, so the UI keeps its own font.
        font_size = 15;
      };
    in
    {
      xdg.configFile = {
        "herdr-app/themes/alduin.json".text = builtins.toJSON theme;
        "herdr-app/fonts/creeper8x15r.otf".source = "${creeper-otf}/share/fonts/opentype/creeper8x15r.otf";
        "herdr-app/fonts/creeper8x15b.otf".source = "${creeper-otf}/share/fonts/opentype/creeper8x15b.otf";
      };

      # The app writes settings.json from its Settings screen, so merge into it.
      home.activation.herdrLook = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        if [[ ! -v DRY_RUN ]]; then
          settings=${home}/settings.json
          mkdir -p ${home}
          { cat "$settings" 2>/dev/null || echo '{}'; } \
            | ${lib.getExe pkgs.jq} '. + ${builtins.toJSON look}' > "$settings.new"
          mv "$settings.new" "$settings"
        fi
      '';
    };
}
