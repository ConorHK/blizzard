{
  perSystem =
    { pkgs, ... }:
    let
      python = pkgs.python3.withPackages (p: [
        p.pillow
        p.pywayland
      ]);
      staging = "${pkgs.wayland-protocols}/share/wayland-protocols/staging";
      protocols = [
        "${pkgs.wayland-scanner}/share/wayland/wayland.xml"
        "${staging}/ext-foreign-toplevel-list/ext-foreign-toplevel-list-v1.xml"
        "${staging}/ext-image-capture-source/ext-image-capture-source-v1.xml"
        "${staging}/ext-image-copy-capture/ext-image-copy-capture-v1.xml"
        "${staging}/ext-workspace/ext-workspace-v1.xml"
        "${pkgs.hyprland-protocols}/share/hyprland-protocols/protocols/hyprland-workspace-image-capture-source-v1.xml"
      ];
    in
    {
      packages.ws-thumbs = pkgs.stdenvNoCC.mkDerivation {
        pname = "ws-thumbs";
        version = "0.1.0";
        src = ./ws-thumbs;
        nativeBuildInputs = [
          pkgs.makeWrapper
          pkgs.pkg-config
          pkgs.wayland-scanner
          python
        ];
        buildPhase = ''
          runHook preBuild
          pywayland-scanner -i ${toString protocols} -o ws_thumbs_protocols
          touch ws_thumbs_protocols/__init__.py
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          lib=$out/lib/ws-thumbs
          mkdir -p $lib
          cp -r ws_thumbs.py ws_thumbs_protocols $lib/
          makeWrapper ${python}/bin/python3 $out/bin/ws-thumbs \
            --add-flags "-s $lib/ws_thumbs.py"
          runHook postInstall
        '';
        meta = {
          description = "Capture a Hyprland workspace as a thumbnail";
          mainProgram = "ws-thumbs";
        };
      };
    };
}
