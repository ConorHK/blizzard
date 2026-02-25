{
  username,
  hashedPassword,
  sshKeys,
}:
{
  users.users.${username} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    inherit hashedPassword;
    home = "/home/${username}";
    createHome = true;
    openssh.authorizedKeys.keys = sshKeys;
  };
}
