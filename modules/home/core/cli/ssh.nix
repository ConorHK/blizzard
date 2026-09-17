{ config, ... }:
{
  flake.modules.homeManager.ssh =
    { lib, ... }:
    let
      inherit (lib)
        attrNames
        filterAttrs
        head
        listToAttrs
        mapAttrs
        mapAttrsToList
        nameValuePair
        remove
        ;

      # Rootless service accounts are normal users too; only a keyed one can log in.
      adminUser =
        value:
        value.config.users.users
        |> filterAttrs (_: user: user.isNormalUser && user.openssh.authorizedKeys.keys != [ ])
        |> attrNames
        |> remove "root"
        |> head;

      sshHosts =
        config.flake.nixosConfigurations |> filterAttrs (_: value: value.config.services.openssh.enable);

      hosts =
        sshHosts
        |> mapAttrs (
          _: value: {
            User = adminUser value;

            Port = head value.config.services.openssh.ports;
          }
        );
      localHosts =
        sshHosts
        |> mapAttrs (
          _name: value: {
            User = adminUser value;

            HostName = value.config.networking.ipv4.address;

            Port = head value.config.services.openssh.ports;
          }
        )
        |> mapAttrsToList (name: value: nameValuePair "${name}-local" value)
        |> listToAttrs;

      # Read-only AI account: hosts that define a snoop user get explicit
      # aliases, and adminUser above must keep resolving to the admin.
      snoopHosts =
        sshHosts
        |> filterAttrs (_: value: value.config.users.users ? snoop)
        |> mapAttrs (
          name: value: {
            User = "snoop";

            HostName = name;

            Port = head value.config.services.openssh.ports;

            IdentityFile = "~/.ssh/${name}-snoop";
          }
        )
        |> mapAttrsToList (name: value: nameValuePair "${name}-snoop" value)
        |> listToAttrs;
      snoopLocalHosts =
        sshHosts
        |> filterAttrs (_: value: value.config.users.users ? snoop)
        |> mapAttrs (
          name: value: {
            User = "snoop";

            HostName = value.config.networking.ipv4.address;

            Port = head value.config.services.openssh.ports;

            IdentityFile = "~/.ssh/${name}-snoop";
          }
        )
        |> mapAttrsToList (name: value: nameValuePair "${name}-snoop-local" value)
        |> listToAttrs;
    in
    {
      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;
        settings =
          hosts
          // localHosts
          // snoopHosts
          // snoopLocalHosts
          // {
            "*" = {
              SetEnv.COLORTERM = "truecolor";
              SetEnv.TERM = "xterm-256color";

              # New panes reuse the connection instead of a handshake.
              ControlMaster = "auto";
              ControlPath = "~/.ssh/master-%r@%n:%p";
              ControlPersist = "10m";
            };
          };
      };
    };
}
