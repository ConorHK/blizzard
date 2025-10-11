{
  flake.modules.nixos.sshd =
    { lib, ... }:
    let
      port = 2222;
      keysFile = builtins.readFile (
        builtins.fetchurl {
          url = "https://github.com/conorhk.keys";
          sha256 = "0rfpraagbfpc8h3wiazd3snq931zd0mlsfpvwh6swph4d56vf4xl";
        }
      );
      keysList = builtins.filter (x: x != "") (lib.splitString "\n" keysFile);
    in
    {
      programs.mosh = {
        enable = true;
        openFirewall = true;
      };
      services.openssh = {
        enable = true;
        ports = [ port ];

        settings = {
          # TODO: lockdown
          KbdInteractiveAuthentication = true;
          PasswordAuthentication = true;

          AcceptEnv = "SHELLS COLORTERM";
        };
      };

      # TODO: pull in keys per host
      users.users = {
        goose.openssh.authorizedKeys.keys = keysList;
        root.openssh.authorizedKeys.keys = keysList;
      };
    };
}
