#!/usr/bin/env python3
"""Static file server for the tests: existing files answer 200, others 404.

Usage: static_server.py <port> <directory>

Uses socketserver.TCPServer rather than `python3 -m http.server`, which
does a reverse DNS lookup of the bind address on startup.
"""

import functools
import http.server
import socketserver
import sys


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        pass


def main():
    port, root = int(sys.argv[1]), sys.argv[2]
    handler = functools.partial(QuietHandler, directory=root)
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", port), handler) as httpd:
        print(f"listening on 127.0.0.1:{port}", flush=True)
        httpd.serve_forever()


if __name__ == "__main__":
    main()
