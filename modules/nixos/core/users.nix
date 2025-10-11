{
  flake.modules.nixos.users = {
    users = {
      mutableUsers = false;

      users = {
        root = {
          isSystemUser = true;
          hashedPassword = "$6$W1tE3/h9AFWOXaXi$pGpXeXFoE/Jyi2RzkuiTfr5dA6FQ.R6Mme8sxi5nWXLIrv7R9d5b0cDoqbb830MWkwwdKbGqBo6f3ZoIhCMjA0";
        };

        goose = {
          isNormalUser = true;
          extraGroups = [ "wheel" ];
          hashedPassword = "$6$o/.qISAqaJ2DbFIA$sFd/J56LT46H4CVH6SYKVRIUmK.KaFeePMj0xdPYzCksDc9a1J1VAEQkGJ9jUarAV68GIriIyc94w7qvgHlIp1";
          home = "/home/goose";
          createHome = true;
        };
      };
    };
  };
}
