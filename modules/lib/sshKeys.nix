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
        sha256 = "0dsy8sv3xzvai7lh3im1vr91gymm7p0ngrdys720wcnzgla2a9wi";
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
