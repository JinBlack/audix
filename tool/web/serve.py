#!/usr/bin/env python3
"""Serve a built Flutter web app with cross-origin isolation headers.

The COOP/COEP headers let drift's wasm worker use SharedArrayBuffer.

Usage: python3 tool/web/serve.py [port] [dir]   (defaults: 8087 build/web)
"""
import http.server
import socketserver
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8087
DIRECTORY = sys.argv[2] if len(sys.argv) > 2 else "build/web"


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, *args):
        pass


with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
    print(f"serving {DIRECTORY} on http://127.0.0.1:{PORT}", flush=True)
    httpd.serve_forever()
