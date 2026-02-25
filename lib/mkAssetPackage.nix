pkgs:
{
  name,
  src,
  glob,
  outputDir ? "share/fonts",
}:
pkgs.stdenvNoCC.mkDerivation {
  inherit name src;
  version = "1.0";

  installPhase = ''
    mkdir -p $out/${outputDir}
    cp -r $src/${glob} $out/${outputDir}/
  '';
}
