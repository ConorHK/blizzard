{
  flake.modules.nixos.root = {
    services.userborn.enable = true;
    users = {
      mutableUsers = false;
      users = {
        root = {
          isSystemUser = true;
          hashedPassword = "$6$W1tE3/h9AFWOXaXi$pGpXeXFoE/Jyi2RzkuiTfr5dA6FQ.R6Mme8sxi5nWXLIrv7R9d5b0cDoqbb830MWkwwdKbGqBo6f3ZoIhCMjA0";
        };
      };
    };
  };
}
