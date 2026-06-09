topLevel: {
  flake.modules.nixos.desktop =
    {
      config,
      inputs,
      lib,
      pkgs,
      ...
    }:
    let
      # Vendored from home-manager's lib.hm.generators.toHyprconf so the
      # hyprland config renders without any home-manager involvement.
      toHyprconf =
        {
          attrs,
          indentLevel ? 0,
          importantPrefixes ? [ "$" ],
        }:
        let
          inherit (lib)
            all
            concatMapStringsSep
            concatStrings
            concatStringsSep
            filterAttrs
            foldl
            generators
            hasPrefix
            isAttrs
            isList
            mapAttrsToList
            replicate
            ;

          initialIndent = concatStrings (replicate indentLevel "  ");

          toHyprconf' =
            indent: attrs:
            let
              sections = filterAttrs (_: v: isAttrs v || (isList v && all isAttrs v)) attrs;

              mkSection =
                n: attrs:
                if lib.isList attrs then
                  (concatMapStringsSep "\n" (a: mkSection n a) attrs)
                else
                  ''
                    ${indent}${n} {
                    ${toHyprconf' "  ${indent}" attrs}${indent}}
                  '';

              mkFields = generators.toKeyValue {
                listsAsDuplicateKeys = true;
                inherit indent;
              };

              allFields = filterAttrs (_: v: !(isAttrs v || (isList v && all isAttrs v))) attrs;

              isImportantField =
                n: _: foldl (acc: prev: if hasPrefix prev n then true else acc) false importantPrefixes;

              importantFields = filterAttrs isImportantField allFields;

              fields = builtins.removeAttrs allFields (mapAttrsToList (n: _: n) importantFields);
            in
            mkFields importantFields
            + concatStringsSep "\n" (mapAttrsToList mkSection sections)
            + mkFields fields;
        in
        toHyprconf' initialIndent attrs;

      # Extends the wrappers hyprland module with a structured settings
      # option, the same shape the fragments under flake.modules.wrapper
      # were written for when they lived in home-manager.
      settingsFormat =
        { config, lib, ... }:
        {
          options = {
            settings = lib.mkOption {
              type =
                with lib.types;
                let
                  valueType =
                    nullOr (oneOf [
                      bool
                      int
                      float
                      str
                      path
                      (attrsOf valueType)
                      (listOf valueType)
                    ])
                    // {
                      description = "Hyprland configuration value";
                    };
                in
                valueType;
              default = { };
              description = "Hyprland settings rendered into hypr.conf.";
            };

            importantPrefixes = lib.mkOption {
              type = with lib.types; listOf str;
              default = [
                "$"
                "bezier"
                "name"
                "source"
              ];
              description = "Prefixes of settings to render at the top of the config.";
            };
          };

          config."hypr.conf".content = toHyprconf {
            attrs = config.settings;
            inherit (config) importantPrefixes;
          };
        };

      wrapperModules = topLevel.config.flake.modules.wrapper;

      hyprland =
        (inputs.wrappers.wrapperModules.hyprland.apply {
          imports = [
            settingsFormat
            wrapperModules."hyprland/hosts/${config.networking.hostName}"
          ]
          ++ map (name: wrapperModules."hyprland/${name}") [
            "alacritty"
            "firefox"
            "hyprpaper"
            "keybinds"
            "rules"
            "screenshot"
            "session"
            "settings"
            "swayosd"
            "theme"
            "vicinae"
          ];
          inherit pkgs;
        }).wrapper;
    in
    {
      programs.hyprland = {
        enable = true;
        package = hyprland;
        withUWSM = true;
        xwayland.enable = true;
      };
      programs.uwsm.enable = true;
      security.pam.services.hyprlock = { };
      users = {
        users.greeter.group = "greeter";
        groups.greeter = { };
      };

      services.greetd = {
        enable = true;
        settings = {
          default_session = {
            command = "${lib.getExe pkgs.tuigreet} --remember --cmd '${hyprland}/bin/start-hyprland --path ${lib.getExe hyprland}'";
            user = "greeter";
          };
          initial_session = {
            command = "${hyprland}/bin/start-hyprland --path ${lib.getExe hyprland}";
            user = "goose";
          };
        };
      };
    };
}
