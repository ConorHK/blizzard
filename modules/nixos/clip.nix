let
  port = 7391;
  host = "leprechaun";
in
{
  flake = {
    monitoringChecks.clip = {
      name = "clip";
      url = "tcp://${host}:${toString port}";
      conditions = [ "[CONNECTED] == true" ];
    };

    modules.nixos.clip-server =
      { pkgs, ... }:
      let
        server = pkgs.writers.writePython3Bin "clip-server" { } ''
          import http.server
          import os
          import pathlib
          import re
          import sys

          ROOT = pathlib.Path(os.environ["STATE_DIRECTORY"])
          MAX_BYTES = 1 << 20
          SLOT = re.compile(r"^[A-Za-z0-9._-]{1,64}\Z")


          class Handler(http.server.BaseHTTPRequestHandler):
              protocol_version = "HTTP/1.1"

              def log_request(self, code="-", size="-"):
                  who = self.address_string()
                  print(f"{who} {self.command} {self.path} {code}", flush=True)

              def reply(self, code, body):
                  self.send_response(code)
                  self.send_header("Content-Type", "text/plain; charset=utf-8")
                  self.send_header("Content-Length", str(len(body)))
                  self.end_headers()
                  self.wfile.write(body)

              def slot(self):
                  name = self.path.strip("/") or "default"
                  if not SLOT.match(name):
                      self.close_connection = True
                      self.reply(400, b"bad slot name\n")
                      return None
                  return ROOT / name

              def too_large(self):
                  self.close_connection = True
                  self.reply(413, b"too large\n")

              # curl -T- streams chunked, so Content-Length is often absent.
              def read_chunked(self):
                  parts, total = [], 0
                  while True:
                      size = int(self.rfile.readline(64).split(b";")[0], 16)
                      if size == 0:
                          self.rfile.readline()
                          return b"".join(parts)
                      total += size
                      if total > MAX_BYTES:
                          self.too_large()
                          return None
                      parts.append(self.rfile.read(size))
                      self.rfile.read(2)

              def read_body(self):
                  if "chunked" in self.headers.get("Transfer-Encoding", "").lower():
                      return self.read_chunked()
                  length = int(self.headers.get("Content-Length", 0))
                  if length > MAX_BYTES:
                      self.too_large()
                      return None
                  return self.rfile.read(length)

              def do_GET(self):
                  path = self.slot()
                  if path is None:
                      return
                  try:
                      self.reply(200, path.read_bytes())
                  except FileNotFoundError:
                      self.reply(404, b"empty\n")

              def do_PUT(self):
                  path = self.slot()
                  if path is None:
                      return
                  body = self.read_body()
                  if body is None:
                      return
                  tmp = path.with_name(path.name + ".tmp")
                  tmp.write_bytes(body)
                  tmp.replace(path)
                  self.reply(200, b"")

              do_POST = do_PUT


          class Server(http.server.ThreadingHTTPServer):
              # curl drops the keep-alive socket; that is not a fault worth a traceback.
              def handle_error(self, request, client_address):
                  dropped = (ConnectionResetError, BrokenPipeError)
                  if not isinstance(sys.exc_info()[1], dropped):
                      super().handle_error(request, client_address)


          Server(("", ${toString port}), Handler).serve_forever()
        '';
      in
      {
        # Never opened in the firewall: wg0 and tailscale0 are trusted, everything else drops.
        systemd.services.clip = {
          description = "Shared string mailbox";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          serviceConfig = {
            ExecStart = "${server}/bin/clip-server";
            DynamicUser = true;
            StateDirectory = "clip";
            Restart = "always";
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateDevices = true;
            NoNewPrivileges = true;
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
            ];
            SystemCallFilter = [ "@system-service" ];
          };
        };

      };

    modules.nixos.clip =
      { pkgs, ... }:
      {
        environment.systemPackages = [
          (pkgs.writeShellApplication {
            name = "clip";
            runtimeInputs = [
              pkgs.curl
              pkgs.coreutils
            ];
            text = ''
              slot="''${1:-default}"
              url="''${CLIP_URL:-http://${host}:${toString port}}/$slot"

              # Only a pipe or a file on stdin means write; anything else reads,
              # so a stray `< /dev/null` cannot wipe the slot.
              if [ -p /dev/stdin ] || [ -f /dev/stdin ]; then
                curl -fsS -T - "$url"
                exit
              fi

              # Body to a file, so an empty slot reads as a sentence, not curl's 404.
              body=$(mktemp)
              trap 'rm -f "$body"' EXIT
              code=$(curl -sS -o "$body" -w '%{http_code}' "$url")

              case "$code" in
                200) cat "$body" ;;
                404) echo "clip: slot '$slot' is empty" >&2; exit 1 ;;
                *) echo "clip: server returned $code" >&2; exit 1 ;;
              esac
            '';
          })
        ];
      };
  };
}
