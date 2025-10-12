{
  flake.modules.nixos.fail2ban = {
    services.fail2ban = {
      enable = true;
      maxretry = 5;
      bantime = "24h"; # Ban IPs for one day on the first ban
      bantime-increment = {
        enable = true;
        multipliers = "1 2 4 8 16 32 64";
        overalljails = true; # Calculate the bantime based on all the violations
      };
    };
  };
}
