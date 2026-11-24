# Local stand-in for a remote worker's webhook: verifies the X-Webhook-Signature-V2 HMAC like the real route does.
# usage: remote_stub.py <secret-file> <port-file> <log-file>   (binds 127.0.0.1 on a free port, writes the port, serves forever)
import hashlib, hmac, json, sys, time
from http.server import BaseHTTPRequestHandler, HTTPServer
secret = open(sys.argv[1], "rb").read().rstrip(b"\r\n")
seen = set(); hits = [0]
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def reply(self, code, body=b""):
        self.send_response(code); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        hits[0] += 1
        ts = self.headers.get("X-Webhook-Timestamp", ""); sig = self.headers.get("X-Webhook-Signature-V2", ""); rid = self.headers.get("X-Request-ID", "")
        rec = {"path": self.path, "ct": self.headers.get("Content-Type"), "rid": rid, "ts": ts, "body": raw.decode("utf-8", "replace"), "verdict": ""}
        want = hmac.new(secret, ts.encode() + b"." + raw, hashlib.sha256).hexdigest()
        try: fresh = abs(time.time() - int(ts)) <= 300
        except ValueError: fresh = False
        if self.path != "/webhooks/pm-task" or not hmac.compare_digest(want, sig) or not fresh:
            rec["verdict"] = "404"; self.reply(404, b'{"error":"not found"}')
        else:
            try: b = json.loads(raw)
            except ValueError: b = {}
            ok = raw == json.dumps(b, separators=(",", ":")).encode() and set(b) == {"issue", "mode", "nonce"} and len(b.get("nonce", "")) == 32 \
                 and b.get("mode") in ("start", "followup") and rid.startswith(b.get("issue", "?") + "-")
            if not ok: rec["verdict"] = "400"; self.reply(400, b"{}")
            elif b["issue"].startswith("GATE"): rec["verdict"] = "ignored"; self.reply(200, b'{"status":"ignored","reason":"script","route":"pm-task"}')
            elif b["issue"].startswith("RATE"): rec["verdict"] = "429"; self.reply(429, b"{}")
            elif b["issue"].startswith("ODD"): rec["verdict"] = "odd200"; self.reply(200, b"not json")
            elif b["issue"].startswith("DUP"): rec["verdict"] = "duplicate"; self.reply(200, b'{"status":"duplicate"}')
            elif b["issue"].startswith("FLAKY") and rid not in seen:   # drop the first attempt: the client must retry with a fresh signature
                seen.add(rid); rec["verdict"] = "dropped"; open(sys.argv[3], "a").write(json.dumps(rec) + "\n"); self.connection.close(); return
            elif rid in seen and not b["issue"].startswith("FLAKY"): rec["verdict"] = "duplicate"; self.reply(200, b'{"status":"duplicate","delivery_id":"%s"}' % rid.encode())
            else: seen.add(rid); rec["verdict"] = "202"; self.reply(202, b'{"status":"accepted"}')
        open(sys.argv[3], "a").write(json.dumps(rec) + "\n")
srv = HTTPServer(("127.0.0.1", 0), H)
open(sys.argv[2], "w").write(str(srv.server_address[1]))
srv.serve_forever()
