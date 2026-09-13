{
  inputs,
  self,
  ...
}:
{
  flake.agenix-rekey = inputs.agenix-rekey.configure {
    userFlake = self;
    nixosConfigurations = self.nixosConfigurations // {
      # selkie is a container, not a standalone config.
      selkie = {
        config = self.nixosConfigurations.leprechaun.config.containers.selkie.config;
      };
    };
    inherit (self) homeConfigurations;
  };

  perSystem =
    {
      inputs',
      pkgs,
      ...
    }:
    {
      devenv.shells.default = {
        packages = [
          inputs'.agenix-rekey.packages.default
          pkgs.age-plugin-yubikey
        ];
        # Automatically add rekeyed secrets to git without
        # requiring `agenix rekey -a`
        env.AGENIX_REKEY_ADD_TO_GIT = true;
      };
    };
}
