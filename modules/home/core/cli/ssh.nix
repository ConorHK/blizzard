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
            user =
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
          name: value: {
            user =
              value.config.users.users
              |> filterAttrs (_: value: value.isNormalUser)
              |> attrNames
              |> remove "root"
              |> head;

            hostname = value.config.networking.ipv4.address;

            port = head value.config.services.openssh.ports;
          }
        )
        |> mapAttrsToList (name: value: nameValuePair "${name}-local" value)
        |> listToAttrs;
    in
    {
      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;
        matchBlocks =
          hosts
          // localHosts
          // {
            "*" = {
              setEnv.COLORTERM = "truecolor";
              setEnv.TERM = "xterm-256color";
            };
          };
      };
    };
}
