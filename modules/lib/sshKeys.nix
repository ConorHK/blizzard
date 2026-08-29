{ lib, ... }:
{
  # Authorized SSH public keys, fetched once from GitHub at eval time.
  # Single source of truth shared by the NixOS `blizzard.sshKeys` option
  # (modules/nixos/core/ssh-keys.nix) and the installer ISO (modules/flake/iso.nix).
  # The pinned `sha256` keeps this pure-eval safe; bump it when the keys change.
  flake.lib.conorhkSshKeys =
    lib.pipe
      (builtins.fetchurl {
        url = "https://github.com/conorhk.keys";
        sha256 = "0qsz89gpccdric9bav69kw3vrhnj7ahsq6mdb1d3js6ywpjgvk5i";
      })
      [
        builtins.readFile
        (lib.splitString "\n")
        (builtins.filter (x: x != ""))
      ]
    # Not published on GitHub.
    ++ [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJC0hbyeb1uaX+SyTDEBsIC/U72sCswjnRS+flLi+gNf phone@conorknowles.com"
    ];
}
