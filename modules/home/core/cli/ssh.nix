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

      hosts =
        config.flake.nixosConfigurations
        |> filterAttrs (_: value: value.config.services.openssh.enable)
        |> mapAttrs (
          _: value: {
            User =
              value.config.users.users
              |> filterAttrs (_: value: value.isNormalUser)
              |> attrNames
              |> remove "root"
              |> head;
          }
        );
      localHosts =
        config.flake.nixosConfigurations
        |> filterAttrs (_: value: value.config.services.openssh.enable)
        |> mapAttrs (
          _name: value: {
            User =
              value.config.users.users
              |> filterAttrs (_: value: value.isNormalUser)
              |> attrNames
              |> remove "root"
              |> head;

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
