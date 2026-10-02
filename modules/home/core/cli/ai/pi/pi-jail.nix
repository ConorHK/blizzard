{
  # Allowlist jail: OS read-only, home hidden.
  # Workspace and ~/.pi/agent stay writable.
  flake.lib.mkPiJail =
    pkgs:
    {
      package,
      network ? true,
      hostLoopback ? false,
      newSession ? true,
      allow ? [ ],
      readOnly ? [ ],
      extraBwrapArgs ? [ ],
    }:
    let
      inherit (pkgs) lib;
      pastaFlags = [
        "--config-net"
        "--quiet"
        # No inbound forwards.
        "-t"
        "none"
        "-u"
        "none"
      ]
      ++ lib.optionals (!hostLoopback) [
        "--no-map-gw"
        "-T"
        "none"
        "-U"
        "none"
      ];
      pi = lib.getExe package;
    in
    pkgs.writeShellApplication {
      name = "pi-jail";
      runtimeInputs = [
        pkgs.bubblewrap
        pkgs.coreutils
      ]
      ++ lib.optional network pkgs.passt;
      # Tildes are expanded by expand() below.
      excludeShellChecks = [ "SC2088" ];
      text = ''
        home=$(readlink -f "$HOME")
        cwd=$(readlink -f "$PWD")
        # Binding home rw would defeat the tmpfs.
        case "$home" in
          "$cwd" | "$cwd"/*)
            echo "pi-jail: workspace contains home; refusing" >&2
            exit 1
            ;;
        esac
        args=(
          --ro-bind / /
          # Hides D-Bus, agent and systemd sockets.
          --tmpfs /run
          --proc /proc
          --dev /dev
          --tmpfs /tmp
          --tmpfs "$home"
          --unshare-all
          --die-with-parent
        )
        # NixOS PATH and nix-ld live here.
        if [ -L /run/current-system ]; then
          args+=(--symlink "$(readlink /run/current-system)" /run/current-system)
        fi
        resolv=$(readlink -f /etc/resolv.conf)
        case "$resolv" in
          /run/*) args+=(--ro-bind "$resolv" "$resolv") ;;
        esac
        if [ -n "''${XDG_RUNTIME_DIR-}" ]; then
          args+=(--perms 0700 --dir "$XDG_RUNTIME_DIR")
        fi
        # The daemon trusts by caller uid.
        proxy=/run/pi-nix-daemon/socket
        if [ -S "$proxy" ]; then
          args+=(--ro-bind "$proxy" /nix/var/nix/daemon-socket/socket)
        fi
        ${lib.optionalString newSession "args+=(--new-session)"}
        expand() {
          local p="$1"
          if [[ "$p" == "~/"* ]]; then p="$HOME/''${p#"~/"}"; fi
          printf '%s' "$p"
        }
        # Resolved source, canonical-parent dest: bwrap
        # cannot mount through symlinks.
        bind() {
          local flag="$1" p="$2" src dest
          if [ ! -e "$p" ]; then
            echo "pi-jail: skipping missing $p" >&2
            return 0
          fi
          src=$(readlink -f "$p")
          dest="$(readlink -f "$(dirname "$p")")/$(basename "$p")"
          args+=("$flag" "$src" "$dest")
        }
        bind --bind "$cwd"
        bind --bind "$HOME/.pi/agent"
        # A session cannot rewrite next session's guard.
        bind --ro-bind "$HOME/.pi/agent/extensions"
        bind --ro-bind "$HOME/.nix-profile"
        allow=(${lib.escapeShellArgs allow})
        for p in "''${allow[@]}"; do bind --bind "$(expand "$p")"; done
        ro=(${lib.escapeShellArgs readOnly})
        for p in "''${ro[@]}"; do bind --ro-bind "$(expand "$p")"; done
        extra=(${lib.escapeShellArgs extraBwrapArgs})
        if [ "''${#extra[@]}" -gt 0 ]; then args+=("''${extra[@]}"); fi
      ''
      + (
        if network then
          ''
            # pasta owns the netns; bwrap maps our uid back.
            exec pasta ${lib.escapeShellArgs pastaFlags} -- \
              bwrap "''${args[@]}" --share-net --uid "$(id -u)" --gid "$(id -g)" -- ${pi} "$@"
          ''
        else
          ''
            exec bwrap "''${args[@]}" -- ${pi} "$@"
          ''
      );
    };
}
