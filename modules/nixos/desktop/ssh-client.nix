topLevel: {
  flake.modules.nixos.ssh-client =
    { config, lib, ... }:
    let
      inherit (lib)
        attrNames
        concatMapAttrsStringSep
        concatStringsSep
        filterAttrs
        head
        optionalString
        remove
        ;

      people = filterAttrs (_: user: user.isNormalUser) config.users.users;

      # Rootless service accounts are normal users too; only a keyed one can log in.
      adminUser =
        host:
        head (
          remove "root" (
            attrNames (
              filterAttrs (
                _: user: user.isNormalUser && user.openssh.authorizedKeys.keys != [ ]
              ) host.config.users.users
            )
          )
        );

      sshHosts = filterAttrs (
        _: host: host.config.services.openssh.enable
      ) topLevel.config.flake.nixosConfigurations;

      # Root and service accounts keep the stock client settings.
      match = "Match localuser ${concatStringsSep "," (attrNames people)}";

      entry =
        name: address: host:
        ''
          ${match} originalhost ${name}
            User ${adminUser host}
            Port ${toString (head host.config.services.openssh.ports)}
        ''
        + optionalString (address != null) ''
          HostName ${address}
        '';
    in
    {
      # Nothing may follow these blocks, or it would only apply to the people above.
      programs.ssh.extraConfig = lib.mkAfter (
        concatMapAttrsStringSep "" (name: entry name null) sshHosts
        + concatMapAttrsStringSep "" (
          name: host: entry "${name}-local" host.config.networking.ipv4.address host
        ) sshHosts
        + ''
          ${match}
            SetEnv COLORTERM=truecolor TERM=xterm-256color
            # New panes reuse the connection instead of a handshake.
            ControlMaster auto
            ControlPath ~/.ssh/master-%r@%n:%p
            ControlPersist 10m
        ''
      );
    };
}
