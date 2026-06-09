{ lib, ... }:
let
  base16Scheme = {
    base00 = "#1c1c1c";
    base01 = "#262626";
    base02 = "#626262";
    base03 = "#878787";
    base04 = "#dfdfaf";
    base05 = "#dfdfaf";
    base06 = "#dfdfaf";
    base07 = "#dfdfaf";
    base08 = "#af5f5f";
    base09 = "#af875f";
    base0A = "#af875f";
    base0B = "#87875f";
    base0C = "#87afaf";
    base0D = "#878787";
    base0E = "#af8787";
    base0F = "#87afaf";
  };

  rgb = color: "rgb(${lib.removePrefix "#" color})";
  rgba = color: alpha: "rgba(${lib.removePrefix "#" color}${alpha})";
in
{
  flake.modules = {
    nixos.desktop = _: { stylix.base16Scheme = base16Scheme; };
    homeManager.theme = {
      stylix.base16Scheme = base16Scheme;
    };

    # Mirrors what stylix's hyprland target injected when the config was
    # managed by home-manager; the wrapped hyprland is themed from here.
    wrapper."hyprland/theme".settings = {
      decoration.shadow.color = rgba base16Scheme.base00 "99";

      general."col.inactive_border" = rgb base16Scheme.base03;

      group = {
        "col.border_active" = rgb base16Scheme.base0D;
        "col.border_inactive" = rgb base16Scheme.base03;
        "col.border_locked_active" = rgb base16Scheme.base0C;

        groupbar = {
          text_color = rgb base16Scheme.base05;
          "col.active" = rgb base16Scheme.base0D;
          "col.inactive" = rgb base16Scheme.base03;
        };
      };

      misc.background_color = rgb base16Scheme.base00;
    };
  };
}
