import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.request import urlopen

import orjson  # C extension: exercises the venv copied from python-build


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"ok\n" if self.path == "/healthz" else orjson.dumps(
            {"hello": "python", "uid": os.getuid()}) + b"\n"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):  # stdout/stderr logging is handled by the platform
        pass


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "healthcheck":
        try:
            sys.exit(0 if urlopen("http://127.0.0.1:8080/healthz", timeout=2).status == 200 else 1)
        except Exception:
            sys.exit(1)
    HTTPServer(("", 8080), Handler).serve_forever()
