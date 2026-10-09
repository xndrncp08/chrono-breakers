#!/usr/bin/env python3
"""Serve the Rojo source tree to a running Studio session over loopback.

Studio has no Rojo plugin connection in this setup, so scripts are pushed by asking the Studio MCP
plugin to run tools/studio-sync.luau, which fetches every script listed here and replaces its
Source when it differs. Only 127.0.0.1 is bound; nothing leaves the machine.

Usage: tools/studio-sync.py [project.json] [port]   (defaults: test.project.json 34999)
Then run tools/studio-sync.luau through the MCP `run_luau` tool (edit peer). Ctrl+C to stop.
"""
import http.server
import json
import os
import subprocess
import sys
import tempfile

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
project = sys.argv[1] if len(sys.argv) > 1 else "test.project.json"
port = int(sys.argv[2]) if len(sys.argv) > 2 else 34999

serve_dir = tempfile.mkdtemp(prefix="studio-sync-")
sourcemap = os.path.join(serve_dir, "sourcemap.json")
subprocess.run(["rojo", "sourcemap", project, "-o", sourcemap], cwd=root, check=True, capture_output=True)

entries = []


def walk(node, path):
    for f in node.get("filePaths", []):
        if f.endswith(".luau"):
            entries.append({"path": path, "file": f})
    for child in node.get("children", []):
        walk(child, path + [child["name"]])


walk(json.load(open(sourcemap)), [])


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/manifest.json":
            body = json.dumps([{"id": i, **e} for i, e in enumerate(entries)]).encode()
        elif self.path.startswith("/files/") and self.path.endswith(".luau"):
            index = int(self.path[len("/files/") : -len(".luau")])
            # Read on every request so edits made while the server runs are picked up.
            body = open(os.path.join(root, entries[index]["file"]), "rb").read()
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


print(f"serving {len(entries)} scripts from {project} on http://127.0.0.1:{port}")
http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
