#!/usr/bin/env python3
"""NOVA Payments backend — tiny Flutterwave relay for the NOVA Mobile store.

WHY THIS EXISTS: the Flutterwave SECRET key must never ship inside the game
APK (anyone can extract it). This small server holds the secret key (as an
env var) and does two jobs for the game client:
  1. POST /create-link  {pack_id, amount, currency} -> {link, tx_ref}
     Creates a Flutterwave hosted checkout link for an NOVA Points pack.
  2. GET /verify?tx_ref=... -> {paid: true/false, ...}
     Verifies the transaction server-side before the game credits NP.

DEPLOY: run anywhere always-on (VPS, Render, Fly.io...):
    FLW_SECRET_KEY=FLWSECK-... FLW_PUBLIC_KEY=FLWPUBK-... python3 nova_payments_server.py
Game config (user://flutterwave_config.json) then sets:
    {"mode": "live", "backend_url": "https://your-host:8777"}

Stdlib only. No real money moves until a player completes a checkout.
"""
import hashlib
import hmac
import json
import os
import time
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, HTTPServer

FLW_SECRET = os.environ.get("FLW_SECRET_KEY", "")
FLW_PUBLIC = os.environ.get("FLW_PUBLIC_KEY", "")
PORT = int(os.environ.get("PORT", "8777"))
# Pack catalog mirrors store_defs.gd NP packs (id -> {np, ngn, usd})
PACKS = {
    "np100":  {"np": 100,  "ngn": 1500,  "usd": 1},
    "np500":  {"np": 500,  "ngn": 6500,  "usd": 4},
    "np1100": {"np": 1100, "ngn": 12000, "usd": 8},
    "np2900": {"np": 2900, "ngn": 27500, "usd": 18},
    "np6200": {"np": 6200, "ngn": 50000, "usd": 32},
}


def flw(method, path, payload=None):
    req = urllib.request.Request(
        "https://api.flutterwave.com/v3" + path,
        data=json.dumps(payload).encode() if payload else None,
        method=method,
        headers={"Authorization": "Bearer " + FLW_SECRET,
                 "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        return {"status": "error", "http": e.code,
                "body": e.read().decode()[:300]}


class H(BaseHTTPRequestHandler):
    def _send(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        n = int(self.headers.get("Content-Length", 0) or 0)
        return json.loads(self.rfile.read(n) or b"{}")

    def do_POST(self):
        if self.path == "/create-link":
            if not FLW_SECRET:
                return self._send({"error": "server not configured"}, 500)
            b = self._body()
            pack = PACKS.get(str(b.get("pack_id", "")))
            if not pack:
                return self._send({"error": "unknown pack"}, 400)
            currency = str(b.get("currency", "NGN")).upper()
            amount = pack["ngn"] if currency == "NGN" else pack["usd"]
            tx_ref = "nova_%s_%d" % (b.get("pack_id"), int(time.time() * 1000))
            out = flw("POST", "/payments", {
                "tx_ref": tx_ref, "amount": amount, "currency": currency,
                "redirect_url": str(b.get("redirect_url", "")),
                "customer": {"email": str(b.get("email", ""))},
                "customizations": {"title": "NOVA Points",
                                   "description": "%d NOVA Points" % pack["np"]},
                "meta": {"pack_id": b.get("pack_id"), "np": pack["np"]},
            })
            if out.get("status") == "success":
                return self._send({"link": out["data"]["link"],
                                   "tx_ref": tx_ref})
            return self._send({"error": "flutterwave rejected",
                               "detail": str(out)[:300]}, 502)
        if self.path == "/webhook":
            # Log-and-acknowledge; game polls /verify for the credit decision.
            raw = self.rfile.read(int(self.headers.get("Content-Length", 0) or 0))
            print("webhook:", raw[:300], flush=True)
            return self._send({"ok": True})
        return self._send({"error": "not found"}, 404)

    def do_GET(self):
        if self.path.startswith("/verify"):
            qs = self.path.split("?", 1)[1] if "?" in self.path else ""
            tx_ref = dict(p.split("=", 1) for p in qs.split("&") if "=" in p).get("tx_ref", "")
            if not tx_ref:
                return self._send({"error": "tx_ref required"}, 400)
            out = flw("GET", "/transactions/verify_by_reference?tx_ref=" + tx_ref)
            d = (out.get("data") or {}) if isinstance(out, dict) else {}
            paid = out.get("status") == "success" and d.get("status") == "successful"
            return self._send({"paid": paid,
                               "amount": d.get("amount"),
                               "currency": d.get("currency"),
                               "meta": d.get("meta")})
        if self.path == "/health":
            return self._send({"ok": True, "configured": bool(FLW_SECRET)})
        return self._send({"error": "not found"}, 404)

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    if not FLW_SECRET:
        print("WARNING: FLW_SECRET_KEY not set — /create-link will refuse.")
    HTTPServer(("0.0.0.0", PORT), H).serve_forever()
    print("NOVA payments backend on :%d" % PORT, flush=True)
