{
  flake.modules.homeManager.hyprland = {
    wayland.windowManager.hyprland.settings = {
      windowrule = [
        # Float and center file pickers
        "float on, match:class xdg-desktop-portal-gtk, match:title ^(Open.*Files?|Save.*Files?|All Files|Save)"
        "center on, match:class xdg-desktop-portal-gtk, match:title ^(Open.*Files?|Save.*Files?|All Files|Save)"
        "float on, match:title ^(File Upload)"
        "center on, match:title ^(File Upload)"

        "float on, match:class ^(steam)$"
        "float on, match:class com.saivert.pwvucontrol"
        "center on, match:class com.saivert.pwvucontrol"
      ];
    };
  };
}
