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
        sha256 = "08dn4rsfv1h3baishcsr9iaqkc6l2j2qjg4x356xwsw67c736n7r";
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
