{ config, lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (config.flake.lib) mkUser mkDisko;

      user = mkUser {
        username = "alice";
        hashedPassword = "$6$hash";
        sshKeys = [ "ssh-ed25519 AAAAC3Nz alice@host" ];
      };

      luks = disko: disko.disko.devices.disk.main.content.partitions.luks.content;
      subvolumes = disko: (luks disko).content.subvolumes;

      results = lib.debug.runTests {
        testUserIsNormal = {
          expr = user.users.users.alice.isNormalUser;
          expected = true;
        };

        testUserIsPrivileged = {
          expr = user.users.users.alice.extraGroups;
          expected = [
            "wheel"
            "dialout"
          ];
        };

        testUserHasOwnGroup = {
          expr = {
            group = user.users.users.alice.group;
            declared = builtins.attrNames user.users.groups;
          };
          expected = {
            group = "alice";
            declared = [ "alice" ];
          };
        };

        testUserKeysPassThrough = {
          expr = user.users.users.alice.openssh.authorizedKeys.keys;
          expected = [ "ssh-ed25519 AAAAC3Nz alice@host" ];
        };

        testDiskoDefaultDevice = {
          expr = (mkDisko { }).disko.devices.disk.main.device;
          expected = "/dev/nvme0n1";
        };

        testDiskoDeviceOverride = {
          expr = (mkDisko { device = "/dev/sda"; }).disko.devices.disk.main.device;
          expected = "/dev/sda";
        };

        # Kernels, initrds and the boot random seed must not be world-readable.
        testDiskoEspIsNotWorldReadable = {
          expr = (mkDisko { }).disko.devices.disk.main.content.partitions.ESP.content.mountOptions;
          expected = [
            "defaults"
            "umask=0077"
          ];
        };

        testDiskoWithoutFido2 = {
          expr = (luks (mkDisko { })).settings;
          expected.allowDiscards = true;
        };

        testDiskoWithFido2 = {
          expr =
            (luks (mkDisko {
              fido2 = true;
            })).settings.crypttabExtraOpts;
          expected = [
            "fido2-device=auto"
            "token-timeout=10"
          ];
        };

        testDiskoSubvolumes = {
          expr = builtins.attrNames (subvolumes (mkDisko { }));
          expected = [
            "/home"
            "/log"
            "/nix"
            "/persist"
            "/root"
            "/swap"
          ];
        };

        testDiskoSwapSize = {
          expr = {
            default = (subvolumes (mkDisko { }))."/swap".swap.swapfile.size;
            explicit =
              (subvolumes (mkDisko {
                swapSize = "32G";
              }))."/swap".swap.swapfile.size;
          };
          expected = {
            default = "8G";
            explicit = "32G";
          };
        };
      };
    in
    {
      checks.lib = pkgs.runCommand "lib-tests" { } (
        if results == [ ] then
          "touch $out"
        else
          ''
            echo ${lib.escapeShellArg (builtins.toJSON results)}
            exit 1
          ''
      );
    };
}
