{
  perSystem =
    { pkgs, ... }:
    {
      packages.matrix-gateway = pkgs.buildGoModule {
        pname = "matrix-gateway";
        version = "0.1.0";
        src = ./matrix-gateway;
        vendorHash = "sha256-2lRCg79dCib19Z9iXCVbU9uxsINYMAKRMwxoAq1kQno=";

        # goolm is pure Go, so the deprecated libolm is not needed.
        tags = [ "goolm" ];

        meta.mainProgram = "matrix-gateway";
      };
    };
}
