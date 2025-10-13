{
  flake.modules.nixos.sshd =
    { ... }:
    let
      port = 2222;
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
          PasswordAuthentication = false;

          AcceptEnv = "SHELLS COLORTERM";
        };
      };
    };
}
