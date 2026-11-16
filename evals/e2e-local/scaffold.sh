#!/usr/bin/env bash
# The sample app plus a tiny stdlib HTTP front, so the run has something to start and drive end to end.
set -e
SRC="$(cd "$(dirname "$0")/../../examples/sample-app" && pwd)"
cp -R "$SRC"/. .
cat > server.py <<'PY'
#!/usr/bin/env python3
"""HTTP front for the shortener. Run: PORT=8080 python3 server.py  (GET /health, POST /shorten {"url"}, GET /r/<code>)"""
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

from shortener import Shortener

store = Shortener()


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/shorten":
            return self._send(404, {"error": "not found"})
        length = int(self.headers.get("Content-Length") or 0)
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
            code = store.shorten(body["url"])
        except (ValueError, KeyError, TypeError) as e:
            return self._send(400, {"error": str(e)})
        self._send(201, {"code": code})

    def do_GET(self):
        if self.path == "/health":
            return self._send(200, {"status": "ok"})
        if self.path.startswith("/r/"):
            try:
                url = store.resolve(self.path[3:])
            except KeyError:
                return self._send(404, {"error": "unknown code"})
            self.send_response(302)
            self.send_header("Location", url)
            self.end_headers()
            return
        self._send(404, {"error": "not found"})

    def _send(self, status, obj):
        data = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", int(os.environ.get("PORT", "8080"))), Handler).serve_forever()
PY
printf '\nHTTP front: `PORT=8080 python3 server.py` (GET /health, POST /shorten, GET /r/<code>).\n' >> README.md
git init -q && git add -A && git -c user.email=eval@example.com -c user.name=eval commit -qm init
