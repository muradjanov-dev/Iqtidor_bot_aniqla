#!/usr/bin/env bash
#
# Jitsi Meet -> Oracle Cloud "Always Free" (Ampere ARM, Ubuntu 22.04)
#
# Serverda bitta buyruq bilan ishga tushadi:
#   sudo ./setup.sh --domain meet.example.com --email siz@example.com
#
# Domeni yo'q bo'lsa (self-signed sertifikat, brauzer ogohlantiradi):
#   sudo ./setup.sh --no-letsencrypt
#
set -euo pipefail

DOMAIN=""
EMAIL=""
USE_LETSENCRYPT=1
ENABLE_AUTH=0
JITSI_TAG="${JITSI_TAG:-}"
INSTALL_DIR="${INSTALL_DIR:-/opt/jitsi}"
TZ_NAME="${TZ_NAME:-Asia/Tashkent}"

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mXATO:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Foydalanish: sudo ./setup.sh [parametrlar]

  --domain <domen>     Jitsi uchun domen (masalan meet.example.com yoki
                       maktab.duckdns.org). Let's Encrypt uchun majburiy.
  --email <email>      Let's Encrypt bildirishnomalari uchun email.
  --no-letsencrypt     HTTPS sertifikatsiz (self-signed). Domensiz variant.
  --auth               Faqat ro'yxatdan o'tgan o'qituvchi xona ocha olsin
                       (o'quvchilar mehmon sifatida qo'shiladi).
  --tag <stable-XXXX>  docker-jitsi-meet relizini qo'lda tanlash.
  -h, --help           Shu yordam matni.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)         DOMAIN="${2:-}"; shift 2 ;;
    --email)          EMAIL="${2:-}"; shift 2 ;;
    --no-letsencrypt) USE_LETSENCRYPT=0; shift ;;
    --auth)           ENABLE_AUTH=1; shift ;;
    --tag)            JITSI_TAG="${2:-}"; shift 2 ;;
    -h|--help)        usage; exit 0 ;;
    *) die "Noma'lum parametr: $1 (--help ni ko'ring)" ;;
  esac
done

[[ $EUID -eq 0 ]] || die "root kerak: sudo ./setup.sh ..."

if [[ $USE_LETSENCRYPT -eq 1 ]]; then
  [[ -n "$DOMAIN" ]] || die "--domain kerak (yoki --no-letsencrypt ishlating)"
  [[ -n "$EMAIL"  ]] || die "--email kerak (yoki --no-letsencrypt ishlating)"
fi

# ---------------------------------------------------------------- public IP --
detect_public_ip() {
  local ip=""
  # Oracle instance metadata (eng ishonchli: NAT ortidagi haqiqiy public IP)
  ip="$(curl -fsS -m 5 -H 'Authorization: Bearer Oracle' \
        http://169.254.169.254/opc/v2/vnics/ 2>/dev/null \
        | grep -o '"publicIp"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | head -1 | cut -d'"' -f4 || true)"
  if [[ -z "$ip" ]]; then
    for svc in https://ifconfig.me https://icanhazip.com https://api.ipify.org; do
      ip="$(curl -fsS -m 5 "$svc" 2>/dev/null | tr -d '[:space:]' || true)"
      [[ -n "$ip" ]] && break
    done
  fi
  printf '%s' "$ip"
}

PUBLIC_IP="$(detect_public_ip)"
[[ -n "$PUBLIC_IP" ]] || die "Public IP aniqlanmadi. JVB_ADVERTISE_IPS ni qo'lda yozing."
log "Public IP: $PUBLIC_IP"

if [[ $USE_LETSENCRYPT -eq 1 ]]; then
  resolved="$(getent hosts "$DOMAIN" | awk '{print $1}' | head -1 || true)"
  if [[ "$resolved" != "$PUBLIC_IP" ]]; then
    warn "$DOMAIN -> ${resolved:-topilmadi}, lekin server IP $PUBLIC_IP."
    warn "DNS A yozuvi hali tarqalmagan bo'lsa, Let's Encrypt sertifikat bermaydi."
    warn "5-10 daqiqa kutib qayta ishga tushiring, yoki --no-letsencrypt ishlating."
  fi
fi

# ------------------------------------------------------------------ paketlar --
log "Tizim paketlari yangilanmoqda..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl git jq iptables-persistent >/dev/null

if ! command -v docker >/dev/null 2>&1; then
  log "Docker o'rnatilmoqda..."
  curl -fsSL https://get.docker.com | sh
fi
docker compose version >/dev/null 2>&1 || die "docker compose plugin topilmadi"
systemctl enable --now docker >/dev/null 2>&1 || true

# ---------------------------------------------------------------- firewall ----
# Oracle Ubuntu obrazlarida iptables'da 22-portdan boshqa hamma narsa REJECT.
# Buni ochmasak, Security List'ni ochsangiz ham Jitsi ishlamaydi.
open_port() {
  local proto="$1" port="$2"
  if ! iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null; then
    iptables -I INPUT 1 -p "$proto" --dport "$port" -j ACCEPT
    log "iptables: ${port}/${proto} ochildi"
  fi
}
log "Firewall sozlanmoqda (80/tcp, 443/tcp, 10000/udp)..."
open_port tcp 80
open_port tcp 443
open_port udp 10000
netfilter-persistent save >/dev/null 2>&1 || warn "iptables qoidalari saqlanmadi"

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
  ufw allow 80/tcp    >/dev/null
  ufw allow 443/tcp   >/dev/null
  ufw allow 10000/udp >/dev/null
  log "ufw qoidalari qo'shildi"
fi

# ------------------------------------------------------- docker-jitsi-meet ----
if [[ -z "$JITSI_TAG" ]]; then
  JITSI_TAG="$(curl -fsS -m 10 https://api.github.com/repos/jitsi/docker-jitsi-meet/releases/latest 2>/dev/null \
               | jq -r '.tag_name // empty' || true)"
fi
if [[ -z "$JITSI_TAG" ]]; then
  JITSI_TAG="$(git ls-remote --tags --refs https://github.com/jitsi/docker-jitsi-meet.git 'stable-*' \
               | awk -F/ '{print $NF}' | sort -V | tail -1 || true)"
fi
[[ -n "$JITSI_TAG" ]] || die "docker-jitsi-meet relizi aniqlanmadi. --tag stable-XXXX bering."
log "docker-jitsi-meet relizi: $JITSI_TAG"

mkdir -p "$INSTALL_DIR"
if [[ -d "$INSTALL_DIR/docker-jitsi-meet/.git" ]]; then
  git -C "$INSTALL_DIR/docker-jitsi-meet" fetch --tags --quiet
else
  git clone --quiet https://github.com/jitsi/docker-jitsi-meet.git "$INSTALL_DIR/docker-jitsi-meet"
fi
cd "$INSTALL_DIR/docker-jitsi-meet"
git checkout --quiet "$JITSI_TAG"

CFG_DIR="$INSTALL_DIR/cfg"
mkdir -p "$CFG_DIR"/{web,transcripts,prosody/config,prosody/prosody-plugins-custom,jicofo,jvb,jigasi,jibri}

[[ -f .env ]] || cp env.example .env

# .env ichidagi kalitni yangilaydi (izohga olingan bo'lsa ham).
set_env() {
  local key="$1" value="$2"
  if grep -qE "^#?[[:space:]]*${key}=" .env; then
    sed -i -E "s|^#?[[:space:]]*${key}=.*|${key}=${value}|" .env
  else
    printf '%s=%s\n' "$key" "$value" >> .env
  fi
}

log ".env sozlanmoqda..."
set_env CONFIG               "$CFG_DIR"
set_env TZ                   "$TZ_NAME"
set_env HTTP_PORT            80
set_env HTTPS_PORT           443
set_env JVB_PORT             10000
set_env JVB_ADVERTISE_IPS    "$PUBLIC_IP"
set_env DOCKER_HOST_ADDRESS  "$PUBLIC_IP"
set_env RESTART_POLICY       unless-stopped
set_env ENABLE_HTTP_REDIRECT 1

if [[ $USE_LETSENCRYPT -eq 1 ]]; then
  set_env PUBLIC_URL         "https://${DOMAIN}"
  set_env DISABLE_HTTPS      0
  set_env ENABLE_LETSENCRYPT 1
  set_env LETSENCRYPT_DOMAIN "$DOMAIN"
  set_env LETSENCRYPT_EMAIL  "$EMAIL"
else
  set_env PUBLIC_URL         "https://${PUBLIC_IP}"
  set_env DISABLE_HTTPS      0
  set_env ENABLE_LETSENCRYPT 0
fi

if [[ $ENABLE_AUTH -eq 1 ]]; then
  set_env ENABLE_AUTH   1
  set_env ENABLE_GUESTS 1
  set_env AUTH_TYPE     internal
fi

# Parollar faqat bir marta generatsiya qilinadi (qayta ishga tushirish xavfsiz).
if grep -qE '^JICOFO_AUTH_PASSWORD=$|^JICOFO_AUTH_PASSWORD=[[:space:]]*$' .env; then
  log "Parollar generatsiya qilinmoqda..."
  ./gen-passwords.sh
fi

# ------------------------------------------------------------------- ishga ----
log "Konteynerlar tortib olinmoqda va ishga tushirilmoqda (bir necha daqiqa)..."
docker compose pull --quiet
docker compose up -d

cat > "$INSTALL_DIR/jitsi" <<CTL
#!/usr/bin/env bash
# Jitsi boshqaruvi: jitsi start|stop|restart|logs|status|update
cd "$INSTALL_DIR/docker-jitsi-meet" || exit 1
case "\${1:-status}" in
  start)   docker compose up -d ;;
  stop)    docker compose down ;;
  restart) docker compose down && docker compose up -d ;;
  logs)    docker compose logs -f --tail=100 ;;
  status)  docker compose ps ;;
  update)  docker compose down && git fetch --tags && docker compose pull && docker compose up -d ;;
  *) echo "jitsi start|stop|restart|logs|status|update"; exit 1 ;;
esac
CTL
chmod +x "$INSTALL_DIR/jitsi"
ln -sf "$INSTALL_DIR/jitsi" /usr/local/bin/jitsi

echo
log "Tayyor."
echo
if [[ $USE_LETSENCRYPT -eq 1 ]]; then
  echo "  Manzil:  https://${DOMAIN}"
  echo "  Sertifikat 1-3 daqiqada olinadi. Kuzatish: docker compose logs -f web"
else
  echo "  Manzil:  https://${PUBLIC_IP}"
  echo "  Self-signed sertifikat: brauzer ogohlantiradi, 'Advanced -> Proceed' bosiladi."
fi
echo "  Boshqaruv: jitsi status | jitsi logs | jitsi restart | jitsi update"
if [[ $ENABLE_AUTH -eq 1 ]]; then
  echo
  echo "  O'qituvchi akkaunti yarating:"
  echo "    cd $INSTALL_DIR/docker-jitsi-meet"
  echo "    docker compose exec prosody /usr/bin/prosodyctl --config /config/prosody.cfg.lua \\"
  echo "      register ustoz meet.jitsi KUCHLI_PAROL"
fi
echo
echo "  Oracle Console -> VCN -> Security List da quyidagilar ochiq bo'lsin:"
echo "    0.0.0.0/0  TCP 80, TCP 443, UDP 10000"
