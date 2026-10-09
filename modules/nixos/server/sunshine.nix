{
  flake.modules.nixos.sunshine = {
    services.sunshine = {
      enable = true;
      autoStart = true;
      capSysAdmin = true;
      openFirewall = true;
      # Portal capture pops the share picker at login.
      settings.capture = "kms";
    };
  };
}
