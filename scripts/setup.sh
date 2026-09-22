#!/usr/bin/env bash
#
# Botni ishga tushirishning hamma qadami — bitta buyruqda.
#
#   ./scripts/setup.sh https://iqtidor-bot-aniqla.vercel.app
#
# Nima qiladi:
#   1. BOT_TOKEN ni so'raydi (yoki .env dan oladi) va haqiqiyligini tekshiradi
#   2. WEBHOOK_SECRET yasaydi
#   3. ADMIN_ID ni so'raydi
#   4. Hammasini .env ga yozadi (git'ga tushmaydi)
#   5. Vercel CLI bo'lsa — o'zgaruvchilarni Vercel'ga yuboradi va redeploy qiladi
#   6. Telegram webhook'ini ulaydi va tekshiradi
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.env"

ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mXATO:\033[0m %s\n' "$*" >&2; exit 1; }

command -v python3 >/dev/null || die "python3 topilmadi"
command -v curl    >/dev/null || die "curl topilmadi"

# .env dan o'qiydi (faqat kerakli kalitlarni).
read_env() {
  local key="$1"
  [[ -f "$ENV_FILE" ]] || return 0
  sed -nE "s/^[[:space:]]*${key}=[[:space:]]*//p" "$ENV_FILE" | tail -1 | tr -d "\"'" | tr -d '\r'
}

# .env ga yozadi yoki yangilaydi.
write_env() {
  local key="$1" value="$2"
  touch "$ENV_FILE"
  if grep -qE "^[[:space:]]*${key}=" "$ENV_FILE"; then
    python3 - "$ENV_FILE" "$key" "$value" <<'PY'
import re, sys
path, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, encoding="utf-8") as fh:
    text = fh.read()
# lambda: qiymatdagi \ va \1 kabi ketma-ketliklar maxsus ma'no olmasligi uchun
text = re.sub(rf"(?m)^[ \t]*{re.escape(key)}=.*$", lambda _: f"{key}={value}", text)
with open(path, "w", encoding="utf-8") as fh:
    fh.write(text)
PY
  else
    printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
  fi
}

BASE_URL="${1:-}"

# ------------------------------------------------------------- 1. BOT_TOKEN --
info "1/6  Bot tokeni"
BOT_TOKEN="${BOT_TOKEN:-$(read_env BOT_TOKEN)}"
if [[ -z "$BOT_TOKEN" ]]; then
  read -rsp "  @BotFather bergan tokenni kiriting (ekranda ko'rinmaydi): " BOT_TOKEN
  echo
fi
[[ -n "$BOT_TOKEN" ]] || die "token kiritilmadi"

BOT_USERNAME="$(curl -fsS -m 15 "https://api.telegram.org/bot${BOT_TOKEN}/getMe" 2>/dev/null \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result']['username'] if d.get('ok') else '')" 2>/dev/null || true)"
[[ -n "$BOT_USERNAME" ]] || die "token ishlamadi. @BotFather -> /token dan yangisini oling."
ok "token to'g'ri: @${BOT_USERNAME}"

# -------------------------------------------------------- 2. WEBHOOK_SECRET --
info "2/6  Webhook maxfiy kaliti"
WEBHOOK_SECRET="${WEBHOOK_SECRET:-$(read_env WEBHOOK_SECRET)}"
if [[ -z "$WEBHOOK_SECRET" ]]; then
  WEBHOOK_SECRET="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
  ok "yangi kalit yasaldi"
else
  ok "mavjud kalit ishlatiladi"
fi

# --------------------------------------------------------------- 3. ADMIN_ID --
info "3/6  Administrator ID"
ADMIN_ID="${ADMIN_ID:-$(read_env ADMIN_ID)}"
if [[ -z "$ADMIN_ID" ]]; then
  echo "  Telegram ID'ingizni bilmasangiz @userinfobot ga /start yozing."
  read -rp "  Telegram ID: " ADMIN_ID
fi
[[ "$ADMIN_ID" =~ ^-?[0-9]+$ ]] || die "ADMIN_ID faqat raqam bo'lishi kerak"
ok "ADMIN_ID = $ADMIN_ID"

# ------------------------------------------------------------------ 4. .env --
info "4/6  .env yangilanmoqda"
write_env BOT_TOKEN      "$BOT_TOKEN"
write_env WEBHOOK_SECRET "$WEBHOOK_SECRET"
write_env ADMIN_ID       "$ADMIN_ID"
chmod 600 "$ENV_FILE" 2>/dev/null || true
if git -C "$ROOT" ls-files --error-unmatch .env >/dev/null 2>&1; then
  warn ".env hali git'da kuzatilyapti! Bajaring: git rm --cached .env && git commit -m 'untrack .env'"
else
  ok ".env yozildi va git'ga tushmaydi"
fi

# ---------------------------------------------------------------- 5. Vercel --
info "5/6  Vercel o'zgaruvchilari"
if command -v vercel >/dev/null 2>&1; then
  if vercel whoami >/dev/null 2>&1; then
    for pair in "BOT_TOKEN=$BOT_TOKEN" "WEBHOOK_SECRET=$WEBHOOK_SECRET" "ADMIN_ID=$ADMIN_ID"; do
      key="${pair%%=*}"; value="${pair#*=}"
      vercel env rm "$key" production --yes >/dev/null 2>&1 || true
      if printf '%s' "$value" | vercel env add "$key" production >/dev/null 2>&1; then
        ok "$key Vercel'ga yozildi"
      else
        warn "$key yozilmadi — qo'lda qo'shing"
      fi
    done
    info "     redeploy qilinmoqda..."
    vercel --prod --yes >/dev/null 2>&1 && ok "redeploy tugadi" || warn "redeploy bo'lmadi — Vercel panelidan Redeploy bosing"
  else
    warn "Vercel CLI tizimga kirmagan. Bajaring: vercel login && vercel link"
    warn "Keyin shu skriptni qayta ishga tushiring."
  fi
else
  warn "Vercel CLI yo'q. O'rnatish: npm i -g vercel"
  warn "Yoki qo'lda: Vercel -> Settings -> Environment Variables ga quyidagilarni qo'ying:"
  echo "       BOT_TOKEN      = (tokeningiz)"
  echo "       WEBHOOK_SECRET = $WEBHOOK_SECRET"
  echo "       ADMIN_ID       = $ADMIN_ID"
  echo "     keyin Deployments -> ... -> Redeploy"
fi

# --------------------------------------------------------------- 6. Webhook --
info "6/6  Webhook ulanmoqda"
if [[ -z "$BASE_URL" ]]; then
  read -rp "  Vercel manzilingiz (masalan https://iqtidor-bot-aniqla.vercel.app): " BASE_URL
fi
BASE_URL="${BASE_URL%/}"
[[ "$BASE_URL" == https://* ]] || die "manzil https:// bilan boshlanishi kerak"
[[ "$BASE_URL" == */api/telegram ]] || BASE_URL="${BASE_URL}/api/telegram"

BOT_TOKEN="$BOT_TOKEN" WEBHOOK_SECRET="$WEBHOOK_SECRET" \
  python3 "$ROOT/scripts/set_webhook.py" "$BASE_URL"

echo
info "Tekshiruv"
BOT_TOKEN="$BOT_TOKEN" python3 "$ROOT/scripts/set_webhook.py" --info

echo
ok "Tayyor. Telegram'da @${BOT_USERNAME} ga /dars deb yozing."
echo "   Javob kelmasa yuqoridagi last_error_message qatorini o'qing."
