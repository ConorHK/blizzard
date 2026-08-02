{
  flake.modules.wrapper."hyprland/rules".settings = {
    windowrule = [
      # Float and center file pickers
      "float on, match:class xdg-desktop-portal-gtk, match:title ^(Open.*Files?|Save.*Files?|All Files|Save)"
      "center on, match:class xdg-desktop-portal-gtk, match:title ^(Open.*Files?|Save.*Files?|All Files|Save)"
      "float on, match:title ^(File Upload)"
      "center on, match:title ^(File Upload)"

      # Float Firefox extension popups (Bitwarden, etc.) and Picture-in-Picture;
      # let normal browser windows tile. Extension popout windows are titled
      # "Extension: (<name>) ... — Mozilla Firefox".
      "float on, match:class ^(firefox)$, match:title ^(Extension:.*)"
      "center on, match:class ^(firefox)$, match:title ^(Extension:.*)"
      "float on, match:class ^(firefox)$, match:title ^(Picture-in-Picture)$"

      # Float only the Steam Friends List; let the main window tile
      "float on, match:class ^(steam)$, match:initial_title ^(Friends List)$"
      "float on, match:class com.saivert.pwvucontrol"
      "center on, match:class com.saivert.pwvucontrol"
    ];
  };
}
