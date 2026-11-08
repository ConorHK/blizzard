{
  flake.modules.nixos.sunshine = {
    services.sunshine = {
      enable = true;
      autoStart = true;
      capSysAdmin = true;
      openFirewall = true;
      settings = {
        # Portal capture pops the share picker at login.
        capture = "kms";
        # Ultra low latency Vulkan tuning.
        vk_tune = 3;
        # Wired LAN rarely drops packets, so spend less bitrate on recovery.
        fec_percentage = 10;
      };
    };
  };
}
