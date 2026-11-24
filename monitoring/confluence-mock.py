#!/usr/bin/env python3
"""
Confluence Data Center mock for the Perfana demo (Confluence report publishing).

Implements the REST calls Perfana's "Publish to Confluence" makes against Data Center, under the
context path /confluence like a real install:

  GET  /confluence/rest/api/space/<key>                   connection test (space lookup)
  POST /confluence/rest/api/content                       create a page (storage format)
  GET  /confluence/rest/api/content/<id>?expand=version   current version, before an update
  PUT  /confluence/rest/api/content/<id>                  update a page (version must be n+1)
  GET  /confluence/rest/api/content/<id>/child/attachment list attachments (id, title)
  POST /confluence/rest/api/content/<id>/child/attachment add attachments (multipart); a name already
                                                          on the page is refused, as on real DC
  POST /confluence/rest/api/content/<id>/child/attachment/<attId>/data  replace one attachment
  PUT  /confluence/rest/api/content/<id>/child/attachment 405, as on real DC (that create-or-replace
                                                          PUT exists on Cloud only)

And, so "Open the page in Confluence" lands somewhere, a browsable view:

  GET  /confluence/                                       list of published pages
  GET  /confluence/pages/viewpage.action?pageId=<id>      the page, storage format rendered to HTML
  GET  /confluence/download/attachments/<id>/<file>       an attachment

Auth: Bearer $CONFLUENCE_TOKEN (default mock-token), like a Data Center personal access token.
The browsable view needs no auth. Spaces: $SPACES (default PERF), so any other key is a 404.
Pages live in memory; a restart empties the space.

Standard library only, so it runs on python:3.13-alpine with no build step.
"""

import html
import json
import os
import re
import threading
import time
from email.parser import BytesParser
from email.policy import HTTP
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, quote, unquote, urlparse

PORT = int(os.environ.get("PORT", "8091"))
TOKEN = os.environ.get("CONFLUENCE_TOKEN", "mock-token")
SPACES = {k.strip(): i for i, k in enumerate(os.environ.get("SPACES", "PERF").split(","), start=98305) if k.strip()}
CTX = "/confluence"

lock = threading.Lock()
pages = {}  # id -> {"title", "version", "storage", "space", "parent", "attachments": {name: bytes}}
# Ids start from the boot time, so a restart (which empties the space) never hands out an id a
# report still remembers from before it; Perfana would otherwise update an unrelated page in place.
next_id = [int(time.time())]


def render_storage(page_id, storage):
    """Storage format -> plain HTML, close enough to read what Perfana published."""
    colours = {"Green": ("#e3fcef", "#006644"), "Red": ("#ffebe6", "#bf2600"), "Yellow": ("#fffae6", "#974f0c"),
               "Blue": ("#deebff", "#0747a6"), "Grey": ("#dfe1e6", "#42526e")}

    def status(m):
        bg, fg = colours.get(m.group(1), colours["Grey"])
        return (f'<span style="background:{bg};color:{fg};font-size:11px;font-weight:700;padding:1px 5px;'
                f'border-radius:3px;text-transform:uppercase">{m.group(2)}</span>')

    s = re.sub(r'<ac:structured-macro ac:name="status"><ac:parameter ac:name="colour">(\w+)</ac:parameter>'
               r'<ac:parameter ac:name="title">(.*?)</ac:parameter></ac:structured-macro>', status, storage)
    s = re.sub(r'<ac:structured-macro ac:name="info"><ac:rich-text-body>(.*?)</ac:rich-text-body></ac:structured-macro>',
               r'<div class="info">\1</div>', s, flags=re.S)
    s = re.sub(r'<ac:structured-macro ac:name="expand"><ac:parameter ac:name="title">(.*?)</ac:parameter><ac:rich-text-body>',
               r'<details open><summary>\1</summary>', s)
    s = s.replace("</ac:rich-text-body></ac:structured-macro>", "</details>")
    s = re.sub(r'<ac:image(?: ac:width="(\d+)")?><ri:attachment ri:filename="([^"]+)" /></ac:image>',
               lambda m: f'<img src="{CTX}/download/attachments/{page_id}/{quote(m.group(2))}" '
                         f'style="max-width:100%" width="{m.group(1) or ""}" alt="{m.group(2)}">', s)
    return s


PAGE_CSS = ("body{font-family:-apple-system,'Segoe UI',sans-serif;max-width:1000px;margin:24px auto;padding:0 16px;"
            "color:#172b4d;font-size:14px}table{border-collapse:collapse;margin:8px 0}td,th{border:1px solid #c1c7d0;"
            "padding:4px 8px;text-align:left}th{background:#f4f5f7}.info{background:#deebff;padding:8px 12px;"
            "border-radius:3px}.bar{color:#6b778c;font-size:12px;border-bottom:1px solid #dfe1e6;padding-bottom:8px}")


class Handler(BaseHTTPRequestHandler):
    server_version = "ConfluenceMock/1.0"

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} {fmt % args}", flush=True)

    # --- helpers ---------------------------------------------------------------------------------

    def send_json(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def send_html(self, body, status=200):
        data = f"<!doctype html><meta charset=utf-8><style>{PAGE_CSS}</style>{body}".encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def error(self, status, message):
        self.send_json(status, {"statusCode": status, "message": message})

    def body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length) if length else b""

    def authorized(self):
        if self.headers.get("Authorization") == f"Bearer {TOKEN}":
            return True
        self.error(401, "Unauthorized")
        return False

    def links(self, page_id):
        host = self.headers.get("Host", f"localhost:{PORT}")
        return {"base": f"http://{host}{CTX}", "webui": f"/pages/viewpage.action?pageId={page_id}"}

    # --- routes ----------------------------------------------------------------------------------

    def do_GET(self):
        url = urlparse(self.path)
        path = url.path
        if path in ("/health", f"{CTX}/health"):
            return self.send_json(200, {"status": "ok"})
        if path in (CTX, f"{CTX}/"):
            return self.view_index()
        if path == f"{CTX}/pages/viewpage.action":
            return self.view_page(parse_qs(url.query).get("pageId", [""])[0])
        m = re.fullmatch(rf"{CTX}/download/attachments/(\d+)/(.+)", path)
        if m:
            return self.view_attachment(m.group(1), unquote(m.group(2)))

        if not self.authorized():
            return
        m = re.fullmatch(rf"{CTX}/rest/api/space/([^/]+)", path)
        if m:
            key = unquote(m.group(1))
            if key not in SPACES:
                return self.error(404, f"No space with key : {key}")
            return self.send_json(200, {"id": SPACES[key], "key": key, "name": f"{key} Performance Reports"})
        if path == f"{CTX}/rest/api/content":
            # Find pages by space and title, as Perfana does to walk a system's parent page path.
            # expand=ancestors lists the chain root first, so the last entry is the direct parent.
            q = parse_qs(url.query)
            key, title = q.get("spaceKey", [""])[0], q.get("title", [""])[0]
            results = []
            for pid, p in pages.items():
                if p["space"] != key or p["title"] != title:
                    continue
                chain, cur = [], p["parent"]
                while cur and cur in pages:
                    chain.insert(0, {"id": cur, "type": "page", "title": pages[cur]["title"]})
                    cur = pages[cur]["parent"]
                results.append({"id": pid, "type": "page", "title": p["title"], "ancestors": chain})
            return self.send_json(200, {"results": results, "size": len(results)})
        m = re.fullmatch(rf"{CTX}/rest/api/content/(\d+)/child/attachment", path)
        if m:
            page = pages.get(m.group(1))
            if not page:
                return self.error(404, "No content found with id")
            results = [{"id": f"att{m.group(1)}-{n}", "type": "attachment", "title": n} for n in page["attachments"]]
            return self.send_json(200, {"results": results, "size": len(results)})
        m = re.fullmatch(rf"{CTX}/rest/api/content/(\d+)", path)
        if m:
            page = pages.get(m.group(1))
            if not page:
                return self.error(404, "No content found with id")
            return self.send_json(200, {"id": m.group(1), "type": "page", "title": page["title"],
                                        "version": {"number": page["version"]}, "_links": self.links(m.group(1))})
        self.error(404, f"mock: no route GET {path}")

    def do_POST(self):
        path = urlparse(self.path).path
        if not self.authorized():
            return
        m = re.fullmatch(rf"{CTX}/rest/api/content/(\d+)/child/attachment", path)
        if m:
            return self.save_attachments(m.group(1), replace=None)
        m = re.fullmatch(rf"{CTX}/rest/api/content/(\d+)/child/attachment/att\d+-(.+)/data", path)
        if m:
            return self.save_attachments(m.group(1), replace=unquote(m.group(2)))
        if path != f"{CTX}/rest/api/content":
            return self.error(404, f"mock: no route POST {path}")
        try:
            req = json.loads(self.body())
            key = req["space"]["key"]
            title = req["title"]
            storage = req["body"]["storage"]["value"]
        except (ValueError, KeyError, TypeError):
            return self.error(400, "Bad request: expected type, title, space.key and body.storage.value")
        if key not in SPACES:
            return self.error(404, f"No space with key : {key}")
        parent = (req.get("ancestors") or [{}])[0].get("id")
        with lock:
            if any(p["space"] == key and p["title"] == title for p in pages.values()):
                return self.error(400, f"A page with this title already exists: A page already exists with the "
                                       f"title {title} in the space with key {key}")
            page_id = str(next_id[0])
            next_id[0] += 1
            pages[page_id] = {"title": title, "version": 1, "storage": storage, "space": key, "parent": parent,
                              "attachments": {}}
        self.send_json(200, {"id": page_id, "type": "page", "title": title, "version": {"number": 1},
                             "_links": self.links(page_id)})

    def do_PUT(self):
        path = urlparse(self.path).path
        if not self.authorized():
            return
        m = re.fullmatch(rf"{CTX}/rest/api/content/(\d+)/child/attachment", path)
        if m:
            return self.error(405, "Method Not Allowed")
        m = re.fullmatch(rf"{CTX}/rest/api/content/(\d+)", path)
        if not m:
            return self.error(404, f"mock: no route PUT {path}")
        page = pages.get(m.group(1))
        if not page:
            return self.error(404, "No content found with id")
        try:
            req = json.loads(self.body())
            number = int(req["version"]["number"])
            storage = req["body"]["storage"]["value"]
        except (ValueError, KeyError, TypeError):
            return self.error(400, "Bad request: expected version.number and body.storage.value")
        with lock:
            if number != page["version"] + 1:
                return self.error(409, f"Version must be incremented: current {page['version']}, got {number}")
            page.update(version=number, storage=storage, title=req.get("title", page["title"]))
        self.send_json(200, {"id": m.group(1), "type": "page", "title": page["title"],
                             "version": {"number": number}, "_links": self.links(m.group(1))})

    def save_attachments(self, page_id, replace):
        """POST to the collection adds (refusing a name already there); POST .../<attId>/data replaces."""
        page = pages.get(page_id)
        if not page:
            return self.error(404, "No content found with id")
        # Confluence's XSRF check: a multipart write without this header is refused.
        if self.headers.get("X-Atlassian-Token") != "no-check":
            return self.error(403, "XSRF check failed")
        ctype = self.headers.get("Content-Type", "")
        msg = BytesParser(policy=HTTP).parsebytes(f"Content-Type: {ctype}\r\n\r\n".encode() + self.body())
        parts = [p for p in (msg.iter_parts() if msg.is_multipart() else []) if p.get_filename()]
        if replace is not None and replace not in page["attachments"]:
            return self.error(404, "No attachment with that id")
        if replace is None:
            taken = [p.get_filename() for p in parts if p.get_filename() in page["attachments"]]
            if taken:
                return self.error(400, f"Cannot add a new attachment with same file name as an existing attachment: {taken[0]}")
        saved = []
        for part in parts:
            name = replace if replace is not None else part.get_filename()
            page["attachments"][name] = part.get_payload(decode=True)
            saved.append(name)
        if not saved:
            return self.error(400, "No file parts in the request")
        self.send_json(200, {"results": [{"id": f"att{page_id}-{n}", "type": "attachment", "title": n} for n in saved], "size": len(saved)})

    # --- browsable view --------------------------------------------------------------------------

    def view_index(self):
        rows = "".join(
            f'<tr><td><a href="{CTX}/pages/viewpage.action?pageId={pid}">{html.escape(p["title"])}</a></td>'
            f'<td>{p["space"]}</td><td>{p["version"]}</td><td>{len(p["attachments"])}</td></tr>'
            for pid, p in sorted(pages.items(), key=lambda kv: int(kv[0]), reverse=True))
        body = rows or '<tr><td colspan="4">Nothing published yet.</td></tr>'
        self.send_html(f"<h1>Confluence mock</h1><p class=bar>Spaces: {', '.join(SPACES)} · pages are kept in "
                       f"memory until the container restarts</p><table><tr><th>Title</th><th>Space</th>"
                       f"<th>Version</th><th>Attachments</th></tr>{body}</table>")

    def view_page(self, page_id):
        page = pages.get(page_id)
        if not page:
            return self.send_html(f'<h1>Page not found</h1><p><a href="{CTX}/">All pages</a></p>', 404)
        self.send_html(f'<p class=bar><a href="{CTX}/">Confluence mock</a> / {page["space"]} · version '
                       f'{page["version"]} · {len(page["attachments"])} attachment(s)</p>'
                       f'<h1>{html.escape(page["title"])}</h1>{render_storage(page_id, page["storage"])}')

    def view_attachment(self, page_id, name):
        data = pages.get(page_id, {}).get("attachments", {}).get(name)
        if data is None:
            return self.error(404, "No such attachment")
        self.send_response(200)
        self.send_header("Content-Type", "image/png" if name.endswith(".png") else "application/octet-stream")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    print(f"Confluence mock on :{PORT}{CTX} (spaces: {', '.join(SPACES)})", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
