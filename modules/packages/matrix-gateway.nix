{
  perSystem =
    { pkgs, ... }:
    {
      packages.matrix-gateway = pkgs.buildGoModule {
        pname = "matrix-gateway";
        version = "0.1.0";
        src = ./matrix-gateway;
        vendorHash = "sha256-AxN0+9U78wumC4XsfLBiwwmUBOUQjtDtMuL56MBi/2I=";

        # goolm is pure Go, so the deprecated libolm is not needed.
        tags = [ "goolm" ];

        meta.mainProgram = "matrix-gateway";
      };
    };
}
