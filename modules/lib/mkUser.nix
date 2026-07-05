_: {
  flake.lib.mkUser =
    {
      username,
      hashedPasswordFile,
      sshKeys,
    }:
    {
      users.users.${username} = {
        isNormalUser = true;
        group = username;
        extraGroups = [
          "wheel"
          "dialout"
        ];
        inherit hashedPasswordFile;
        home = "/home/${username}";
        createHome = true;
        openssh.authorizedKeys.keys = sshKeys;
      };
      users.groups.${username} = { };
    };
}
