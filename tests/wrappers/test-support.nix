{
  # Runs a terminal program in a pty and passes once it draws the given text.
  flake.testSupport.ptyExpect =
    pkgs:
    let
      script = pkgs.writeText "pty-expect.py" ''
        import fcntl
        import os
        import pty
        import select
        import struct
        import sys
        import termios
        import time

        needle = sys.argv[1].encode()
        pid, fd = pty.fork()
        if pid == 0:
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 200, 0, 0))
            os.execvp(sys.argv[2], sys.argv[2:])

        seen = b""
        deadline = time.monotonic() + 30
        while needle not in seen and time.monotonic() < deadline:
            if not select.select([fd], [], [], 1)[0]:
                continue
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                break
            if not chunk:
                break
            seen += chunk
        os.kill(pid, 9)
        if needle not in seen:
            sys.exit(f"{needle!r} not drawn; last output: {seen[-2000:]!r}")
      '';
    in
    "${pkgs.python3}/bin/python3 ${script}";
}
