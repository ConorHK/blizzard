{
  inputs,
  self,
  ...
}:
{
  flake.agenix-rekey = inputs.agenix-rekey.configure {
    userFlake = self;
    inherit (self) nixosConfigurations;
  };

  perSystem =
    {
      inputs',
      pkgs,
      ...
    }:
    {
      devshells.default = {
        packages = [
          inputs'.agenix-rekey.packages.default
          pkgs.age-plugin-yubikey
        ];
        env = [
          {
            # Automatically add rekeyed secrets to git without
            # requiring `agenix rekey -a`
            name = "AGENIX_REKEY_ADD_TO_GIT";
            value = true;
          }
        ];
      };
    };
}
