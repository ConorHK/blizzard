{
  nixpkgs.allowedUnfreePackages = [ "discord" ];

  flake.modules.nixos.desktop =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.vesktop ];

      environment.etc = {
        "vesktop/settings.json".source = ./settings.json;
        "vesktop/blizzard.css".source = ./blizzard.css;
      };

      # Vesktop keeps its login beside these files, so they are linked into its own directory.
      # L never replaces a file Vesktop wrote itself, and the /etc targets follow each rebuild.
      systemd.user.tmpfiles.rules = [
        "d %h/.config/vesktop/settings 0755 - - -"
        "d %h/.config/vesktop/themes 0755 - - -"
        "L %h/.config/vesktop/settings/settings.json - - - - /etc/vesktop/settings.json"
        "L %h/.config/vesktop/themes/blizzard.css - - - - /etc/vesktop/blizzard.css"
      ];
    };
}
