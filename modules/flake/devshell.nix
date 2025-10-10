{ inputs, ... }:
{
  imports = [
    inputs.devshell.flakeModule
  ];

  perSystem =
    {
      ...
    }:
    {
      devshells.default = {
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
        ];
      };
    };
}
