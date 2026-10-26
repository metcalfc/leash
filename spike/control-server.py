#!/usr/bin/env python3
"""A temporary, key-free host listener for the VM network positive control."""
import http.server
import sys
from pathlib import Path


class Control(http.server.BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        body = b"leash-host-control\n"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args: object) -> None:
        pass


server = http.server.HTTPServer(("127.0.0.1", int(sys.argv[2])), Control)
Path(sys.argv[1]).write_text(str(server.server_port))
server.serve_forever()
