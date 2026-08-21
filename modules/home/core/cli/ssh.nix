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
    in
    {
      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;
        settings =
          hosts
          // localHosts
          // {
            "*" = {
              SetEnv.COLORTERM = "truecolor";
              SetEnv.TERM = "xterm-256color";
            };
          };
      };
    };
}
