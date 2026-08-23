{
  flake.modules.nixos.sshd =
    { lib, ... }:
    let
      port = 22;
    in
    {
      programs.mosh = {
        enable = lib.mkDefault true;
        # mosh stays tailnet-only; sshd is reachable on every interface.
        openFirewall = lib.mkDefault false;
      };
      services.openssh = {
        enable = lib.mkDefault true;
        openFirewall = lib.mkDefault true;
        ports = [ port ];
        allowSFTP = false;

        settings = {
          KbdInteractiveAuthentication = false;
          PasswordAuthentication = false;

          # Drop dead/idle sessions after 2 missed keepalives (10 min).
          # Note: ClientAliveCountMax 0 would *disable* termination entirely.
          ClientAliveInterval = 300;
          ClientAliveCountMax = 2;

          AllowTcpForwarding = false;
          AllowAgentForwarding = false;
          MaxAuthTries = 3;
          MaxSessions = 2;
          TCPKeepAlive = false;

          KexAlgorithms = [
            "mlkem768x25519-sha256"
            "sntrup761x25519-sha512@openssh.com"
            "curve25519-sha256"
            "curve25519-sha256@libssh.org"
            "ecdh-sha2-nistp521"
            "ecdh-sha2-nistp384"
            "ecdh-sha2-nistp256"
            "diffie-hellman-group-exchange-sha256"
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
        };
      };
    };
}
