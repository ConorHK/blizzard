{
  flake.modules.homeManager.core =
    { lib, pkgs, ... }:
    {
      home.packages = lib.attrValues {
        inherit (pkgs)
          fd
          file
          httpie
          jq
          netcat
          net-snmp
          ripgrep
          sshuttle
          unzip
          ;
      };
    };
}
