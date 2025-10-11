{
  flake.modules.homeManager.hyprlock = {
    programs.hyprlock = {
      enable = true;
      settings = {
        general = {
          disable_loading_bar = true;
          hide_cursor = true;
          no_fade_in = false;
        };
        input-field = {
          size = "600, 100";
          position = "0, 0";
          halign = "center";
          valign = "center";

          outline_thickness = 4;

          placeholder_text = "Enter password";
          fail_text = "<i>$PAMFAIL ($ATTEMPTS)</i>";
          fade_on_empty = false;
        };
      };
    };
  };
}
