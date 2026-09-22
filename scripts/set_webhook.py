#!/usr/bin/env python3
"""Telegram webhook'ini Vercel manziliga ulaydi (yoki holatini ko'rsatadi).

    python3 scripts/set_webhook.py https://loyiha.vercel.app/api/telegram
    python3 scripts/set_webhook.py --info
    python3 scripts/set_webhook.py --delete

BOT_TOKEN va WEBHOOK_SECRET muhit o'zgaruvchilaridan olinadi (.env dan ham).
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

API = "https://api.telegram.org/bot{token}/{method}"


def load_dotenv(path: Path) -> None:
    """.env dan o'qiydi. Tashqi paketga bog'lanmaslik uchun qo'lda."""
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        os.environ.setdefault(key.strip(), value.strip().strip("'\""))


def call(token: str, method: str, payload: dict | None = None) -> dict:
    request = urllib.request.Request(
        API.format(token=token, method=method),
        data=json.dumps(payload).encode("utf-8") if payload else None,
        headers={"Content-Type": "application/json"},
        method="POST" if payload else "GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as exc:
        return json.loads(exc.read() or b'{"ok": false}')


def main() -> int:
    load_dotenv(Path(__file__).resolve().parents[1] / ".env")

    token = os.environ.get("BOT_TOKEN", "").strip()
    if not token:
        print("XATO: BOT_TOKEN topilmadi (.env yoki muhit o'zgaruvchisi).")
        return 1

    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 1

    if args[0] == "--info":
        info = call(token, "getWebhookInfo")
        print(json.dumps(info.get("result", info), indent=2, ensure_ascii=False))
        return 0

    if args[0] == "--delete":
        print(call(token, "deleteWebhook", {"drop_pending_updates": False}))
        return 0

    url = args[0]
    if not url.startswith("https://"):
        print("XATO: manzil https:// bilan boshlanishi kerak.")
        return 1

    payload: dict = {"url": url, "allowed_updates": ["message"]}
    secret = os.environ.get("WEBHOOK_SECRET", "").strip()
    if secret:
        payload["secret_token"] = secret
    else:
        print("Eslatma: WEBHOOK_SECRET sozlanmagan — webhook'ni himoyalash tavsiya etiladi.")

    result = call(token, "setWebhook", payload)
    if result.get("ok"):
        print(f"Webhook ulandi: {url}")
        return 0
    print(f"XATO: {result}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
