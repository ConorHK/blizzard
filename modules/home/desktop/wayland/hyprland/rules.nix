{
  flake.modules.wrapper."hyprland/rules".settings = {
    windowrule = [
      # Float and center file pickers
      "float on, match:class xdg-desktop-portal-gtk, match:title ^(Open.*Files?|Save.*Files?|All Files|Save)"
      "center on, match:class xdg-desktop-portal-gtk, match:title ^(Open.*Files?|Save.*Files?|All Files|Save)"
      "float on, match:title ^(File Upload)"
      "center on, match:title ^(File Upload)"

      # Float only the Steam Friends List; let the main window tile
      "float on, match:class ^(steam)$, match:title ^(Friends List)$"
      "float on, match:class com.saivert.pwvucontrol"
      "center on, match:class com.saivert.pwvucontrol"
    ];
  };
}
