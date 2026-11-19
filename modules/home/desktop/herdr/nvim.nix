{ inputs, ... }:
{
  # herdr-nvim: a file tree in the Files panel with the tab's own nvim beside it.
  flake.modules.homeManager.herdr =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (inputs.self.packages.${pkgs.stdenv.hostPlatform.system}) herdr-app herdr-nvim;
      home = "${config.xdg.configHome}/herdr-app";
      mods = "${herdr-nvim}/share/herdr-app/mods";
      # The mods run this; it tells the binary where its Lua and the app live.
      wrapper = pkgs.writeShellScript "herdr-nvim-app" ''
        export HERDR_NVIM_HOST=app
        export HERDR_NVIM_SELF=${home}/mods/herdr-nvim/bin/herdr-nvim
        export HERDR_NVIM_PLUGIN_ROOT=${herdr-nvim}
        export HERDR_APP_BIN=${lib.getExe herdr-app}
        export HERDR_APP_HOME=${home}
        exec ${lib.getExe herdr-nvim} "$@"
      '';
      sync = {
        id = "herdr-nvim-sync";
        content = {
          mod = "herdr-nvim";
          props.role = "sync";
        };
        edge = "bottom";
        align = "end";
      };
      json = v: lib.escapeShellArg (builtins.toJSON v);
      # keys.json on Linux matches the Super key only as super, never as cmd.
      super = if pkgs.stdenv.hostPlatform.isDarwin then "cmd" else "super";
    in
    {
      programs.herdr-app.keys.global = {
        "${super}-e" = "mod.open:herdr-nvim";
        "${super}-o" = "herdr-nvim.pick";
        "${super}-shift-e" = "herdr-nvim.reveal";
      };

      xdg.configFile = config.lib.herdr.modFiles "herdr-nvim" "${mods}/herdr-nvim" // {
        "herdr-app/mods/herdr-nvim/bin/herdr-nvim".source = wrapper;
      };

      # With no herdr-nvim in the Files slot, mod.open toggles the tab's nvim alone.
      home.activation.herdrNvimLayout = lib.hm.dag.entryAfter [ "herdrSidebar" ] ''
        layout=${home}/layouts/${config.lib.herdr.home}.json
        if [[ -f "$layout" && ! -v DRY_RUN ]]; then
          ${lib.getExe pkgs.jq} --argjson sync ${json sync} '
            .floating = ([.floating[]? | select(.id != "herdr-nvim-sync")] + [$sync])' \
            "$layout" > "$layout.new"
          mv "$layout.new" "$layout"
        fi
      '';
    };
}
