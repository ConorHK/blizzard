"""Serve bounded, atomic clipboard slots."""

import http.server
import os
import pathlib
import re
import socket
import sys
import tempfile

ROOT = pathlib.Path(os.environ.get("STATE_DIRECTORY", "/var/lib/clip"))
MAX_BYTES = 1 << 20
SLOT = re.compile(r"[A-Za-z0-9._-]{1,64}\Z")


class InvalidBody(Exception):
    """Reject malformed request framing."""


class Handler(http.server.BaseHTTPRequestHandler):
    """Handle clipboard reads and writes."""

    protocol_version = "HTTP/1.1"

    def setup(self) -> None:
        """Bound idle request time."""
        super().setup()
        self.connection.settimeout(10)

    def log_request(self, code: int | str = "-", size: int | str = "-") -> None:
        """Record request outcomes."""
        print(f"{self.address_string()} {self.command} {self.path} {code}", flush=True)

    def reply(self, code: int, body: bytes) -> None:
        """Send a bounded response."""
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def slot(self) -> pathlib.Path | None:
        """Validate the slot name."""
        name = self.path.strip("/") or "default"
        if not SLOT.fullmatch(name) or name in {".", "..", ".pending"}:
            self.close_connection = True
            self.reply(400, b"bad slot name\n")
            return None
        return ROOT / name

    def too_large(self) -> None:
        """Reject oversized payloads."""
        self.close_connection = True
        self.reply(413, b"too large\n")

    def read_exact(self, length: int) -> bytes:
        """Reject truncated payloads."""
        data = self.rfile.read(length)
        if len(data) != length:
            raise InvalidBody
        return data

    def read_chunked(self) -> bytes | None:
        """Read bounded HTTP chunks."""
        parts, total = [], 0
        while True:
            line = self.rfile.readline(8193)
            if len(line) > 8192 or not line.endswith(b"\r\n"):
                raise InvalidBody
            size_text = line[:-2].split(b";", 1)[0]
            if not re.fullmatch(rb"[0-9a-fA-F]+", size_text):
                raise InvalidBody
            try:
                size = int(size_text, 16)
            except ValueError as error:
                raise InvalidBody from error
            if size == 0:
                trailer_bytes = 0
                while True:
                    trailer = self.rfile.readline(8193)
                    trailer_bytes += len(trailer)
                    if trailer_bytes > 8192 or not trailer.endswith(b"\r\n"):
                        raise InvalidBody
                    if trailer == b"\r\n":
                        return b"".join(parts)
            total += size
            if total > MAX_BYTES:
                self.too_large()
                return None
            parts.append(self.read_exact(size))
            if self.read_exact(2) != b"\r\n":
                raise InvalidBody

    def read_body(self) -> bytes | None:
        """Validate framing before reading."""
        lengths = self.headers.get_all("Content-Length", [])
        encodings = self.headers.get_all("Transfer-Encoding", [])
        if len(lengths) > 1 or len(encodings) > 1 or (lengths and encodings):
            raise InvalidBody
        if encodings:
            if encodings[0].lower() != "chunked":
                raise InvalidBody
            return self.read_chunked()
        raw = lengths[0] if lengths else "0"
        if not re.fullmatch(r"[0-9]+", raw):
            raise InvalidBody
        try:
            length = int(raw)
        except ValueError as error:
            raise InvalidBody from error
        if length > MAX_BYTES:
            self.too_large()
            return None
        return self.read_exact(length)

    def do_GET(self) -> None:
        """Read one clipboard slot."""
        path = self.slot()
        if path is None:
            return
        try:
            self.reply(200, path.read_bytes())
        except FileNotFoundError:
            self.reply(404, b"empty\n")

    def do_PUT(self) -> None:
        """Replace one slot atomically."""
        path = self.slot()
        if path is None:
            return
        try:
            body = self.read_body()
        except (InvalidBody, ValueError, TimeoutError):
            self.close_connection = True
            self.reply(400, b"bad request body\n")
            return
        if body is None:
            return
        pending = ROOT / ".pending"
        pending.mkdir(mode=0o700, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=pending, delete=False) as stream:
            tmp = pathlib.Path(stream.name)
            try:
                stream.write(body)
                stream.flush()
                tmp.replace(path)
            finally:
                tmp.unlink(missing_ok=True)
        self.reply(200, b"")

    do_POST = do_PUT


class Server(http.server.ThreadingHTTPServer):
    """Ignore routine disconnected clients."""

    def handle_error(
        self, request: socket.socket, client_address: tuple[str, int]
    ) -> None:
        """Suppress routine disconnect tracebacks."""
        if not isinstance(sys.exc_info()[1], (ConnectionResetError, BrokenPipeError)):
            super().handle_error(request, client_address)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("port", type=int)
    Server(("", parser.parse_args().port), Handler).serve_forever()
