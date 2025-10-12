{
  flake.modules.nixos.uptime-kuma =
    { lib, ... }:
    {
      services.uptime-kuma = {
        enable = true;
        settings = {
          HOST = lib.mkDefault "127.0.0.1";
          PORT = lib.mkDefault "3001";
        };
      };
    };
}
