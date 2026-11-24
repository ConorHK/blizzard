topLevel: {
  flake.modules.nixos.home-manager =
    {
      config,
      inputs,
      lib,
      options,
      ...
    }:
    let
      inherit (config.networking) hostName;
    in
    {
      imports = [
        inputs.home-manager.nixosModules.home-manager
      ];

      home-manager = {
        backupFileExtension = "bak";

        useGlobalPkgs = true;
        useUserPackages = true;

        users.goose.imports = [
          topLevel.config.flake.modules.homeManager.core
          # Stylix opt-in target list. The stylix HM module itself is provided
          # by the NixOS stylix home-manager integration, so we import only the
          # target settings here (not the full `theme` module) to avoid a
          # double import conflicting on the read-only `stylix.base16`.
          # Hosts without the stylix NixOS module (servers) skip it.
          (lib.optionalAttrs (options ? stylix) (topLevel.config.flake.modules.homeManager.stylix or { }))
          (topLevel.config.flake.modules.homeManager."homeConfigurations/${hostName}" or { })
        ];

        extraSpecialArgs.inputs = inputs;
      };

      # No shell config in $HOME sources Home Manager's session variables, so logins read them here.
      environment.extraInit = lib.mkAfter ''
        if [ -e "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh" ]; then
          . "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh"
        fi
      '';
    };
}
