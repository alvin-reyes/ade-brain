# A stand-in for Ollama's /api/embed: deterministic bag-of-words vectors, so tests need no model.
import hashlib, json, math, re, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
DIM = 64
def vec(t):
    v = [0.0] * DIM
    for w in re.findall(r"[a-z0-9]+", t.lower().replace("search_document:", "").replace("search_query:", "")):
        v[int(hashlib.md5(w.encode()).hexdigest(), 16) % DIM] += 1.0
    n = math.sqrt(sum(x * x for x in v)) or 1.0
    return [x / n for x in v]
class H(BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        inp = body["input"] if isinstance(body["input"], list) else [body["input"]]
        open(sys.argv[2], "a").write(body["model"] + "\n")
        out = json.dumps({"embeddings": [vec(t) for t in inp]}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(out)
    def log_message(self, *a): pass
s = HTTPServer(("127.0.0.1", 0), H); open(sys.argv[1], "w").write(str(s.server_port)); s.serve_forever()
