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

            read -p 'Enter boot mode on left side and press any key to continue...'

            sudo mount /dev/sda1 /mnt

            if [ ! -f /mnt/INFO_UF2.txt ]; then
              echo "INFO_UF2.txt not found, exiting."
              sudo umount /mnt
              exit 1
            fi

            sudo cp "$HOME/repositories/elora/left.uf2" /mnt

            sudo umount /mnt

            read -p 'Enter boot mode on right side and press any key to continue...'

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
