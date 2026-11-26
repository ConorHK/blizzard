{
  perSystem =
    { pkgs, ... }:
    {
      packages.git-url = pkgs.writeShellApplication {
        name = "git-url";
        runtimeInputs = with pkgs; [
          git
          coreutils
          gnused
        ];
        text = builtins.readFile ./git-url/git-url.sh;
        meta.description = "Print the forge URL for a file and lines";
      };
    };
}
