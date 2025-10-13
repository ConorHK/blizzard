{ inputs, ... }:
{
  imports = [
    inputs.devshell.flakeModule
  ];

  perSystem =
    {
      inputs',
      ...
    }:
    {
      devshells.default = {
        packages = [
          inputs'.home-manager.packages.default
        ];
        commands = [
          {
            name = "rebuild";
            command = ''
              hostname=$1

              echo -e "\n=> Deploying system '$hostname'"
              nh os switch \
                  --hostname $hostname \
                  --target-host root@$hostname \
                  --build-host root@$hostname
            '';
          }
          {
            name = "rebuild-home";
            command = ''
              home=$1

              echo -e "\n=> Deploying home configuration '$home'"
              home-manager switch --flake .#$home \
                  --extra-experimental-features pipe-operators
            '';
          }
        ];
      };
    };
}
