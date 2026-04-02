{ ... }:
{
  flake.lib.mkUser =
    {
      username,
      hashedPassword,
      sshKeys,
    }:
    {
      users.users.${username} = {
        isNormalUser = true;
        group = username;
        extraGroups = [ "wheel" ];
        inherit hashedPassword;
        home = "/home/${username}";
        createHome = true;
        openssh.authorizedKeys.keys = sshKeys;
      };
      users.groups.${username} = { };
    };
}
