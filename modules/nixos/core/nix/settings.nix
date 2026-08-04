{ inputs, ... }:
{
  flake.modules.nixos.nix = {
    nix = {
      channel.enable = false;

      # Pin the `nixpkgs` registry entry to this flake's locked nixpkgs so ad-hoc
      # `nix run/shell nixpkgs#…` reuses the already-realised tree instead of
      # refetching. Works together with `flake-registry = ""` below.
      registry.nixpkgs.flake = inputs.nixpkgs;

      gc = {
        automatic = true;
        options = "--delete-older-than 8d";
        dates = "weekly";
        persistent = true;
      };

      optimise = {
        automatic = true;
        # The 03:45 default plus 30min jitter lands on 04:00-04:15, colliding
        # with leprechaun's 03:00 restic run; both are random-read heavy.
        dates = [ "23:15" ];
      };

      settings = {
        experimental-features = "nix-command flakes pipe-operators";

        # --- Determinate Nix tuning -------------------------------------------
        # Evaluate flakes without first copying the whole source tree into the
        # store. Big win for a many-file dotfiles flake (fonts, images, facter
        # JSON); the companion to `eval-cores` (parallel eval, set in
        # determinate.nix). Requires Determinate Nix.
        lazy-trees = true;

        # Never consult the online flake registry: this flake pins everything
        # and `nix.registry.nixpkgs` is set above, so resolution stays offline
        # and deterministic.
        flake-registry = "";

        # Default download buffer (64 MiB) overflows when substituting whole
        # system closures from Cachix, printing "download buffer is full".
        download-buffer-size = 268435456; # 256 MiB
        # ----------------------------------------------------------------------

        max-jobs = "auto";

        # Make legacy nix commands use the XDG base directories instead of creating directories in $HOME.
        use-xdg-base-directories = true;

        # The maximum number of parallel TCP connections used to fetch files from binary caches and by other downloads.
        # It defaults to 25. 0 means no limit.
        http-connections = 128;

        # This option defines the maximum number of substitution jobs that Nix will try to run in
        # parallel. The default is 16. The minimum value one can choose is 1 and lower values will be
        # interpreted as 1.
        max-substitution-jobs = 128;

        # The number of lines of the tail of the log to show if a build fails.
        log-lines = 25;

        # When free disk space in /nix/store drops below min-free during a build, Nix performs a
        # garbage-collection until max-free bytes are available or there is no more garbage.
        # A value of 0 (the default) disables this feature.
        min-free = 128000000; # 128 MB
        max-free = 1000000000; # 1 GB

        # Prevent garbage collection from altering nix-shells managed by nix-direnv
        # https://github.com/nix-community/nix-direnv#installation
        keep-outputs = true;
        keep-derivations = true;

        # Store de-duplication is handled by the scheduled `nix.optimise.automatic`
        # timer above; `auto-optimise-store` would additionally hard-link on every
        # build, which duplicates that work — so it is intentionally left off.

        # Whether to warn about dirty Git/Mercurial trees.
        warn-dirty = false;

        # The timeout (in seconds) for establishing connections in the binary cache substituter.
        # It corresponds to curl’s –connect-timeout option. A value of 0 means no limit.
        connect-timeout = 5;

        builders-use-substitutes = true;

        # If set to true, Nix will fall back to building from source if a binary substitute
        # fails. This is equivalent to the –fallback flag. The default is false.
        fallback = true;
      };
    };
  };
}
