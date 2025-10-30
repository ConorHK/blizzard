{
  flake.modules.nixos.sshd =
    { lib, ... }:
    let
      port = 2222;
    in
    {
      programs.mosh = {
        enable = lib.mkDefault true;
        openFirewall = lib.mkDefault true;
      };
      services.openssh = {
        enable = lib.mkDefault true;
        ports = [ port ];
        allowSFTP = false;

        settings = {
          KbdInteractiveAuthentication = true;
          PasswordAuthentication = false;
          KexAlgorithms = [
            "sntrup761x25519-sha512"
            "sntrup761x25519-sha512@openssh.com"
            "mlkem768x25519-sha256"
          ];
          Ciphers = [
            "chacha20-poly1305@openssh.com"
            "aes256-gcm@openssh.com"
            "aes128-gcm@openssh.com"
            "aes256-ctr"
            "aes192-ctr"
            "aes128-ctr"
          ];
          Macs = [
            "hmac-sha2-512-etm@openssh.com"
            "hmac-sha2-256-etm@openssh.com"
            "umac-128-etm@openssh.com"
            "hmac-sha2-512"
            "hmac-sha2-256"
            "umac-128@openssh.com"
          ];
          AcceptEnv = "SHELLS COLORTERM";
        };

        extraConfig = ''
          ClientAliveCountMax 0
          ClientAliveInterval 300

          AllowTcpForwarding no
          AllowAgentForwarding no
          MaxAuthTries 3
          MaxSessions 2
          TCPKeepAlive no
        '';

      };
    };
}
