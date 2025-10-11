{
  flake.modules.homeManager.hyprland = {
    wayland.windowManager.hyprland.settings = {
      windowrule = [
        # Float and center file pickers
        "float, class:xdg-desktop-portal-gtk, title:^(Open.*Files?|Save.*Files?|All Files|Save)"
        "center, class:xdg-desktop-portal-gtk, title:^(Open.*Files?|Save.*Files?|All Files|Save)"
        "float, title:^(File Upload)"
        "center, title:^(File Upload)"

        "float, class:^(steam)$"
      ];
    };
  };
}
