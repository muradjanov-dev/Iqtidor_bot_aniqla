"""Jitsi uchrashuv havolasini yasash (faqat standart kutubxona).

Server kerak emas: standart holatda ommaviy https://meet.jit.si ishlatiladi.
O'z serveringiz bo'lsa JITSI_BASE_URL ni o'zgartiring:

    export JITSI_BASE_URL=https://meet.example.com
"""

from __future__ import annotations

import os
import secrets
import unicodedata
from urllib.parse import quote, urlencode

DEFAULT_BASE_URL = os.getenv("JITSI_BASE_URL", "https://meet.jit.si")

# Xonaga taxmin qilib kirib bo'lmasligi uchun nom oxiriga tasodifiy qism qo'shamiz.
# Faqat harf va raqam: havola chiroyli ko'rinadi va qo'lda ham yozib bo'ladi.
_SUFFIX_ALPHABET = "abcdefghijkmnpqrstuvwxyz23456789"  # o/0, l/1 chalkashmasligi uchun
_SUFFIX_LENGTH = 8


def _slugify(text: str) -> str:
    """Matnni xona nomiga yaroqli holga keltiradi: 'Fizika 9-A' -> 'fizika-9-a'."""
    normalized = unicodedata.normalize("NFKD", text)
    ascii_only = normalized.encode("ascii", "ignore").decode("ascii").lower()
    slug = "".join(ch if ch.isalnum() else "-" for ch in ascii_only)
    return "-".join(part for part in slug.split("-") if part)


def make_room_name(prefix: str = "iqtidor") -> str:
    """Taxmin qilib bo'lmaydigan xona nomi qaytaradi."""
    base = _slugify(prefix) or "iqtidor"
    suffix = "".join(secrets.choice(_SUFFIX_ALPHABET) for _ in range(_SUFFIX_LENGTH))
    return f"{base}-{suffix}"


def meeting_link(
    room: str | None = None,
    *,
    base_url: str = DEFAULT_BASE_URL,
    display_name: str | None = None,
    start_muted: bool = True,
    prefix: str = "iqtidor",
) -> tuple[str, str]:
    """(havola, xona_nomi) juftligini qaytaradi.

    room berilmasa yangi tasodifiy xona nomi yaratiladi.
    """
    room = room or make_room_name(prefix)

    params: dict[str, str] = {}
    if display_name:
        params['userInfo.displayName'] = f'"{display_name}"'
    if start_muted:
        params["config.startWithAudioMuted"] = "true"
        params["config.startWithVideoMuted"] = "true"

    url = f"{base_url.rstrip('/')}/{quote(room, safe='')}"
    if params:
        url = f"{url}#{urlencode(params)}"
    return url, room


if __name__ == "__main__":
    link, room_name = meeting_link(prefix="dars")
    print(f"Xona: {room_name}")
    print(f"Havola: {link}")
