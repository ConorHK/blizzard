{
  flake.modules.homeManager.core =
    { pkgs, ... }:
    {
      home.packages =
        let
          qmk-flash = pkgs.writeShellScriptBin "qmk-flash" ''
            #!/usr/bin/env bash

            cd "$HOME/repositories/elora" || exit

            qmk userspace-compile

            echo 'Enter boot mode on left side and wait 30 seconds...'
            sleep 30
            echo "Attempting to flash"

            sudo mount /dev/sda1 /mnt

            if [ ! -f /mnt/INFO_UF2.txt ]; then
              echo "INFO_UF2.txt not found, exiting."
              sudo umount /mnt
              exit 1
            fi

            sudo cp "$HOME/repositories/elora/left.uf2" /mnt

            sudo umount /mnt

            echo 'Enter boot mode on left side and wait 30 seconds...'
            sleep 30
            echo "Attempting to flash"

            sudo mount /dev/sda1 /mnt

            if [ ! -f /mnt/INFO_UF2.txt ]; then
              echo "INFO_UF2.txt not found, exiting."
              sudo umount /mnt
              exit 1
            fi

            sudo cp "$HOME/repositories/elora/right.uf2" /mnt

            sudo umount /mnt
            echo "Complete!"
          '';
        in
        [
          pkgs.qmk
          qmk-flash
        ];
    };
}
