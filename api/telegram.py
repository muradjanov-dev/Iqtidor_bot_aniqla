"""Telegram webhook — Vercel serverless function.

Bot doim onlayn turadi, lekin hech qanday server ishlab turmaydi:
Telegram har bir xabarni shu funksiyaga POST qiladi, funksiya javob berib
o'chadi. Kompyuteringiz o'chiq bo'lsa ham bot ishlaydi.

Faqat standart kutubxona ishlatilgan — o'rnatiladigan paket yo'q.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from utils.jitsi_link import DEFAULT_BASE_URL, meeting_link  # noqa: E402

BOT_TOKEN = os.environ.get("BOT_TOKEN", "")
WEBHOOK_SECRET = os.environ.get("WEBHOOK_SECRET", "")
ALLOW_EVERYONE = os.environ.get("ALLOW_EVERYONE", "").strip() == "1"

TELEGRAM_API = "https://api.telegram.org/bot{token}/{method}"
REQUEST_TIMEOUT = 10


def _int_set(raw: str) -> set[int]:
    """\"123, 456\" -> {123, 456}. Noto'g'ri qiymatlar e'tiborsiz qoldiriladi."""
    out: set[int] = set()
    for part in raw.replace(";", ",").split(","):
        part = part.strip()
        if part.lstrip("-").isdigit():
            out.add(int(part))
    return out


ALLOWED_IDS = _int_set(os.environ.get("ADMIN_ID", "")) | _int_set(
    os.environ.get("TEACHER_IDS", "")
)

WELCOME = (
    "Salom! Men dars uchun video xona havolasini tayyorlayman.\n\n"
    "/dars — yangi xona ochish\n"
    "/dars Fizika 9-A — nomli xona ochish\n"
    "/help — yordam"
)

HELP = (
    "Qanday ishlaydi:\n\n"
    "1. /dars yozasiz — men havola beraman.\n"
    "2. Havolani birinchi bo'lib SIZ ochasiz va Google yoki GitHub bilan "
    "kirasiz (bir marta, brauzer eslab qoladi).\n"
    "3. Havolani o'quvchilarga yuborasiz — ularga akkaunt kerak emas.\n\n"
    "Darsni boshlaganingizda Security options ichidan parol qo'ying yoki "
    "lobby'ni yoqing — shunda faqat siz ruxsat berganlar kiradi.\n\n"
    "Har dars uchun yangi havola oling: eski havola begonaga tushib qolsa ham "
    "keyingi darsga yaramaydi."
)

DENIED = (
    "Kechirasiz, xona ochish faqat o'qituvchilar uchun.\n"
    "Sizga havolani o'qituvchingiz yuboradi."
)


def _command(text: str) -> tuple[str, str]:
    """'/dars@bot Fizika 9-A' -> ('/dars', 'Fizika 9-A')"""
    text = text.strip()
    if not text.startswith("/"):
        return "", text
    head, _, rest = text.partition(" ")
    command = head.split("@", 1)[0].lower()
    return command, rest.strip()


def _may_open_room(user_id: int) -> bool:
    if ALLOW_EVERYONE:
        return True
    if not ALLOWED_IDS:
        # Hech kim sozlanmagan bo'lsa hammaga ruxsat bermaymiz — xavfsizroq.
        return False
    return user_id in ALLOWED_IDS


def build_reply(update: dict) -> dict | None:
    """Telegram update -> sendMessage payload (yoki javob kerak bo'lmasa None)."""
    message = update.get("message") or update.get("edited_message")
    if not message:
        return None

    text = message.get("text")
    chat = message.get("chat") or {}
    chat_id = chat.get("id")
    if not text or chat_id is None:
        return None

    user_id = (message.get("from") or {}).get("id", 0)
    command, argument = _command(text)

    if command in ("/start", "/help"):
        return {"chat_id": chat_id, "text": WELCOME if command == "/start" else HELP}

    if command != "/dars":
        return None

    if not _may_open_room(user_id):
        return {"chat_id": chat_id, "text": DENIED}

    link, room = meeting_link(prefix=argument or "dars")
    label = argument or "Dars"
    return {
        "chat_id": chat_id,
        "text": (
            f"{label} xonasi tayyor:\n{link}\n\n"
            "Birinchi bo'lib siz kiring va Sign in bosing, "
            "keyin havolani o'quvchilarga yuboring."
        ),
        "disable_web_page_preview": True,
        "reply_markup": {
            "inline_keyboard": [[{"text": "Xonaga kirish", "url": link}]]
        },
    }


def send_message(payload: dict) -> None:
    if not BOT_TOKEN:
        print("BOT_TOKEN sozlanmagan — xabar yuborilmadi")
        return
    request = urllib.request.Request(
        TELEGRAM_API.format(token=BOT_TOKEN, method="sendMessage"),
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as response:
            response.read()
    except urllib.error.HTTPError as exc:
        # Telegram'ga 200 qaytaramiz, aks holda u xabarni qayta-qayta yuboradi.
        print(f"sendMessage xatosi {exc.code}: {exc.read()[:200]!r}")
    except OSError as exc:
        print(f"sendMessage ulanmadi: {exc}")


class handler(BaseHTTPRequestHandler):  # Vercel shu nomni qidiradi
    def _respond(self, code: int, body: str = "ok") -> None:
        data = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:
        self._respond(200, f"Jitsi dars boti ishlayapti. Xona serveri: {DEFAULT_BASE_URL}")

    def do_POST(self) -> None:
        if WEBHOOK_SECRET:
            got = self.headers.get("X-Telegram-Bot-Api-Secret-Token", "")
            if got != WEBHOOK_SECRET:
                self._respond(403, "forbidden")
                return

        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            update = json.loads(raw or b"{}")
        except json.JSONDecodeError:
            self._respond(200)
            return

        try:
            payload = build_reply(update)
            if payload:
                send_message(payload)
        except Exception as exc:  # noqa: BLE001 - webhook hech qachon 500 bermasin
            print(f"handler xatosi: {exc!r}")

        self._respond(200)

    def log_message(self, *args) -> None:  # Vercel loglarini toza saqlaymiz
        pass
