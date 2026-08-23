#!/usr/bin/env python3
"""nAIce Proxy: auth disabled + full API passthrough to Hermes WebUI"""
import json, sys
from http.server import HTTPServer, BaseHTTPRequestHandler
import urllib.request, urllib.error

WEBUI = 'http://localhost:8787'

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health': return self.ok({'status':'ok'})
        if self.path == '/api/auth/status': return self.ok({'auth_enabled':False,'password_auth_enabled':False,'logged_in':True})
        self.proxy()
    def do_POST(self):
        if self.path == '/api/auth/login': return self.ok({'ok':True,'logged_in':True})
        self.proxy()
    def do_DELETE(self):
        self.proxy()
    def do_PUT(self):
        self.proxy()
    def proxy(self):
        try:
            cl = int(self.headers.get('Content-Length',0))
            body = self.rfile.read(cl) if cl>0 else b''
            url = f'{WEBUI}{self.path}'
            print(f'[P] {self.command} {self.path}', file=sys.stderr, flush=True)
            req = urllib.request.Request(url, data=body if self.command in ('POST','PUT') else None, method=self.command)
            req.add_header('Content-Type','application/json')
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = resp.read()
                self.send_response(resp.status)
                self.send_header('Content-Type','application/json')
                self.end_headers()
                self.wfile.write(data)
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            self.send_header('Content-Type','application/json')
            self.end_headers()
            self.wfile.write(e.read())
        except Exception as e:
            print(f'[E] {self.path}: {e}', file=sys.stderr, flush=True)
            self.send_response(502)
            self.end_headers()
            self.wfile.write(json.dumps({'error':str(e)}).encode())
    def ok(self, d):
        self.send_response(200)
        self.send_header('Content-Type','application/json')
        self.end_headers()
        self.wfile.write(json.dumps(d).encode())
    def log_message(self, f, *a): pass

HTTPServer(('0.0.0.0',8453),H).serve_forever()