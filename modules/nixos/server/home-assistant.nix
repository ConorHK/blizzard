{
  flake.modules.nixos.home-assistant =
    { pkgs, blizzardLib, ... }:
    let
      homeAssistantVersion = "stable";
      timezone = "Europe/Dublin";
      usbDevice = "/dev/ttyUSB0";
    in
    blizzardLib.mkRootlessContainer {
      inherit pkgs;
      name = "homeassistant";
      image = "ghcr.io/home-assistant/home-assistant:${homeAssistantVersion}";
      startUid = 165536;
      extraGroups = [
        "bluetooth"
        "dialout"
      ];
      volumes = [
        "/var/lib/homeassistant/config:/config"
        "/etc/localtime:/etc/localtime:ro"
        "/run/dbus:/run/dbus:ro"
      ];
      environment.TZ = timezone;
      extraArgs = [
        "--network=host"
        "--device=${usbDevice}:${usbDevice}"
      ];
    }
    // {
      networking.firewall.allowedTCPPorts = [ 8123 ];
    };
}
