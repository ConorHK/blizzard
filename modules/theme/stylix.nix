{ inputs, lib, ... }:
let
  # Stylix is opt-in here: `autoEnable = false` means no target is themed
  # unless we list it below. This stops new/renamed upstream targets from
  # auto-activating and breaking eval (e.g. the kmscon target writing the
  # removed services.kmscon.{extraConfig,fonts}). Add a target when you want
  # theming for it. The lists below reproduce the targets that were active
  # under autoEnable, so theming is unchanged.
  enableTargets =
    names:
    lib.genAttrs names (_: {
      enable = true;
    });

  nixosTargets = enableTargets [
    "chromium"
    "console"
    "fish"
    "font-packages"
    "fontconfig"
    "glance"
    "gnome-text-editor"
    "grub"
    "gtk"
    "gtksourceview"
    "lightdm"
    "limine"
    "nixos-icons"
    "nixvim"
    "nvf"
    "plymouth"
    "qt"
    "regreet"
    "spicetify"
  ];

  homeTargets = enableTargets [
    "font-packages"
    "fontconfig"
    "glance"
    "gnome"
    "gnome-text-editor"
    "gtk"
    "gtksourceview"
    "nixos-icons"
    "qt"
    "xresources"
  ];

  # Opt-in target list for home-manager. Kept separate from the module that
  # imports the stylix HM module so it can also be applied to the NixOS
  # home-manager integration (which already pulls in the stylix HM module and
  # would otherwise conflict on the read-only `stylix.base16` if imported
  # twice).
  homeStylix =
    { config, ... }:
    let
      inherit (config.lib.stylix) colors;
    in
    {
      stylix = {
        autoEnable = false;
        targets = homeTargets;
      };

      # Stylix's fish target only feeds programs.fish, so the wrapped fish runs its script here.
      wrappers.fish.extraConfig = ''
        source ${colors { templateRepo = inputs.stylix.inputs.base16-fish; }}
        # The escape codes garble tmux and zellij.
        if test -z "$TMUX"; and test -z "$ZELLIJ"
            base16-${colors.slug}
        end
      '';
    };
in
{
  flake.modules = {
    homeManager.stylix = homeStylix;

    nixos.desktop = {
      imports = [ inputs.stylix.nixosModules.stylix ];
      stylix = {
        enable = true;
        autoEnable = false;
        # `autoEnable = false` also disables stylix's package overlays (e.g. the
        # themed nixos-icons logo), which are gated separately. Keep them on.
        overlays.enable = true;
        targets = nixosTargets;
      };
    };

    homeManager.theme = {
      imports = [
        inputs.stylix.homeModules.stylix
        homeStylix
      ];
      stylix.enable = true;
    };
  };
}
