{ inputs, self, ... }:
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
}
