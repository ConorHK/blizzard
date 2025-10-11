{
  flake.modules.homeManager.core =
    { pkgs, ... }:
    {
      home = {
        packages = [
          pkgs.wget
        ];
        shellAliases.wget = "wget --hsts-file=$XDG_DATA_HOME/wget-hsts";
      };
    };
}
