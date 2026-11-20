{
  perSystem =
    {
      lib,
      pkgs,
      self',
      ...
    }:
    let
      mpv = self'.packages.mpv;
      # The settings mpv itself loads, read without playing anything.
      probe = pkgs.writeText "mpv-probe.lua" ''
        print("osd-color " .. tostring(mp.get_property("osd-color")))
        print("uosc-color " .. tostring(mp.get_property_native("script-opts")["uosc-color"]))
        mp.command("quit")
      '';
      run = exe: ''
        timeout 60 ${exe} --idle --vo=null --ao=null --script=${probe} > settings
        grep --quiet --ignore-case 'osd-color #ffdfdfaf' settings
        grep --quiet 'uosc-color background=1c1c1c,.*,success=87875f' settings
      '';
      # umpv passes no options on, so its mpv answers over the socket umpv opens.
      ask = pkgs.writeText "umpv-ask.py" ''
        import json
        import socket
        import sys
        import time

        deadline = time.monotonic() + 30
        while True:
            sock = socket.socket(socket.AF_UNIX)
            try:
                sock.connect(sys.argv[1])
                break
            except OSError:
                sock.close()
                if time.monotonic() > deadline:
                    sys.exit("umpv started no mpv")
                time.sleep(0.2)

        sock.settimeout(10)
        sock.sendall(b'{"command": ["get_property", "osd-color"], "request_id": 1}\n')
        for line in sock.makefile():
            reply = json.loads(line)
            if reply.get("request_id") == 1:
                print("osd-color", reply["data"])
                break
        sock.sendall(b'{"command": ["quit"]}\n')
      '';
    in
    {
      checks.mpv = pkgs.runCommand "mpv-test" { } ''
        export HOME=$TMPDIR UMPV_SOCKET_DIR=$TMPDIR
        ${run (lib.getExe mpv)}
        ${lib.optionalString pkgs.stdenv.hostPlatform.isDarwin (
          run "${mpv}/Applications/mpv.app/Contents/MacOS/mpv"
        )}

        # umpv asks for a window, and the build has no display to give it.
        mkdir --parents $HOME/.config/mpv
        printf 'vo=null\nao=null\n' > $HOME/.config/mpv/mpv.conf
        ${mpv}/bin/umpv
        ${pkgs.python3}/bin/python3 ${ask} $TMPDIR/.umpv > settings
        grep --quiet --ignore-case 'osd-color #ffdfdfaf' settings
        touch "$out"
      '';
    };
}
