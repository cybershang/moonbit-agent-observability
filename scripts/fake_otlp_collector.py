#!/usr/bin/env python3
"""Minimal OTLP/HTTP collector that prints received payloads to stdout.

Accepts POST /v1/traces, /v1/metrics, /v1/logs and returns an empty 200
response so the OTLP exporter treats the export as successful. The request
headers and body preview are printed for verification.
"""

import sys
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def do_POST(self):
        content_length = self.headers.get("Content-Length")
        transfer_encoding = self.headers.get("Transfer-Encoding", "")
        if content_length is not None:
            body = self.rfile.read(int(content_length))
        elif "chunked" in transfer_encoding.lower():
            body = self._read_chunked()
        else:
            body = b""

        print(f"[FAKE-COLLECTOR] {self.path} bytes={len(body)}")
        for key, value in self.headers.items():
            print(f"[FAKE-COLLECTOR]   {key}: {value}")
        if body:
            preview = body[:4096]
            try:
                text = preview.decode("utf-8")
                print(text)
            except UnicodeDecodeError:
                print(preview.hex())
        print("[FAKE-COLLECTOR] --- end ---")
        sys.stdout.flush()

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _read_chunked(self) -> bytes:
        chunks = []
        while True:
            line = self.rfile.readline()
            if not line:
                break
            size_str = line.split(b";", 1)[0].strip()
            if not size_str:
                continue
            try:
                size = int(size_str, 16)
            except ValueError:
                break
            if size == 0:
                # Read trailing headers
                while True:
                    line = self.rfile.readline()
                    if not line or line == b"\r\n":
                        break
                break
            chunks.append(self.rfile.read(size))
            self.rfile.readline()  # trailing CRLF
        return b"".join(chunks)


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", 4318), Handler)
    print("[FAKE-COLLECTOR] Listening on http://0.0.0.0:4318")
    sys.stdout.flush()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
